#!/bin/sh
# platform: host-agnostic -- compiles against the 10.9 and 11.3 SDKs; runs on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Swift's Dispatch" -- under __swift__, <dispatch/dispatch.h> declares the OS_OBJECT_SWIFT3 classes
#       Swift's Dispatch overlay needs, matching 10.9's runtime; Objective-C clients and a newer SDK are untouched.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
src=tests/c/dispatch_swift_classes.m
inc="$T/include/recaulk"
if compiling; then
  D="$(dirname "$(tbin x)")"
  # platform: swiftc's importer defines __swift__ (swift 5.4: 50400) and parses with modules
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -D__swift__=50400 -I"$inc" -c "$src" -o "$D/swift.o" \
    > "$D/swift.log" 2>&1 || { bad "under __swift__, the 10.9 SDK's dispatch types are not the 11.3 classes:"; head -8 "$D/swift.log"; }
  # platform: the 10.9 SDK names its module maps module.map, which clang22 calls deprecated. Swift's own module
  #           setup (a VFS map putting this header in module Dispatch) is swift's to test; this is the plain one.
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -Wno-deprecated-module-dot-map -fmodules -fmodules-cache-path="$D/mc" -I"$inc" \
    -fsyntax-only "$src" > "$D/objc-modules.log" 2>&1 || { bad "an Objective-C client with -fmodules does not parse:"; head -8 "$D/objc-modules.log"; }
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -I"$inc" "$src" -framework Foundation -o "$(tbin classes)" \
    > "$D/objc.log" 2>&1 || { bad "an Objective-C client does not build:"; head -8 "$D/objc.log"; }
  SDK113="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)"
  "$CC" --no-default-config --target=x86_64-apple-macos10.15 -isysroot "$SDK113" -mmacosx-version-min=10.15 -arch x86_64 \
    -Wall -Werror -D__swift__=50400 -I"$inc" -fsyntax-only "$src" > "$D/sdk113.log" 2>&1 \
    || { bad "with the 11.3 SDK, which declares the classes itself, <dispatch/dispatch.h> does not parse under __swift__:"; head -8 "$D/sdk113.log"; }
  [ "$fail" = 0 ] || exit 1
  check_loads "$(tbin classes)"
fi
runtime_half
"$(tbin classes)" || bad "10.9's dispatch runtime differs from the declared classes"
[ "$fail" = 0 ] && echo "dispatch-swift-classes OK"
exit $fail
