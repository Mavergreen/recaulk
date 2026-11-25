#!/bin/sh
# platform: host-agnostic
#   usage: build-standins.sh STAGE_PREFIX WORK_DIR
#          builds libRecaulkAppKit.dylib (lib/stand-in/) from build/standins.txt: each class a shim under its own name,
#          which re-parents itself onto the AppKit class it stands in for where AppKit has it, or installs a stand-in.
# spec: README.md "Stand-in classes" -- an app's subclasses bind each shim two-level and load this dylib strongly
set -eu
umask 022
SELF=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
. "$SELF/lib.sh"
ROOT=$MAVERICKS_ROOT
[ "$#" = 2 ] || { sed -n 3,5p "$0" >&2; exit 2; }
T=$1; W=$2
case "$T:$W" in /*:/*) ;; *) echo 'build-standins: absolute stage/work paths required' >&2; exit 2 ;; esac
[ -n "${SDK:-}" ] || SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")
[ -f "$SDK/SDKSettings.plist" ] || { echo "build-standins: $SDK is not an SDK" >&2; exit 1; }
recaulk_tools
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
LIB=libRecaulkAppKit.dylib
NAME="@rpath/$LIB"

rm -rf "$W"
mkdir -p "$W/objects" "$T/lib/stand-in"
"$CC" --version > "$W/compiler.txt"
printf 'SDK=%s\n' "$SDK" > "$W/sdk.txt"
: > "$W/source-inputs"
grep -v '^#' "$ROOT/build/standins.txt" | awk 'NF' | while read -r mine _; do
  [ -f "$ROOT/src/standins/$mine.m" ] || { echo "build-standins: build/standins.txt names $mine, with no src/standins/$mine.m" >&2; exit 1; }
  # spec: tests/objc-archive-reproducible.sh -- the same prefix maps as librecaulk-objc.a, for the same bytes anywhere
  "$CC" $TARGET_FLAGS -isysroot "$SDK" -fobjc-arc -Os -g -fPIC -Wall -Werror -Wno-deprecated-declarations \
    -ffile-prefix-map="$ROOT/"= -ffile-prefix-map="$W/"= \
    -ffile-prefix-map="$SDK"="$(basename "$SDK")" -fdebug-compilation-dir=. \
    -I"$ROOT/src/objc" -c "$ROOT/src/standins/$mine.m" -o "$W/objects/$mine.o"
  echo "src/standins/$mine.m" >> "$W/source-inputs"
done
# spec: README.md "Stand-in classes" -- an app finds it by @rpath in its own Frameworks. Drydock names each stand-in
#       method by its implementation's local symbol, so nothing here strips them.
"$CC" -dynamiclib $TARGET_FLAGS -isysroot "$SDK" -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -fobjc-arc \
  -o "$T/lib/stand-in/$LIB" "$W"/objects/*.o \
  -install_name "$NAME" -compatibility_version 1.0.0 -current_version 1.0.0 \
  -framework AppKit -framework Foundation -lobjc
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
(cd "$ROOT" && sha256 $(cat "$W/source-inputs") src/objc/accessibility-map.h build/standins.txt build/build-standins.sh) \
  > "$W/source-inputs.txt" || exit 1
(cd "$T" && sha256 lib/stand-in/$LIB) > "$W/products.txt" || exit 1
