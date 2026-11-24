#!/bin/sh
# platform: macOS-only -- materializes with shipyard-cmake and compiles with clang22 against the pinned 10.9 SDK.
# spec: .superpowers/specs/2026-11-24-swift-appkit-recipes-design.md -- NSWindowStyleMaskFullSizeContentView is the one
#       10.10 value the swift-appkit recipes declare; it carries 10.10 availability.
set -eu
cd "$(dirname "$0")/.."
. build/msc.sh
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
d="$(mktemp -d "${TMPDIR:-/tmp}/swift-appkit-availability.XXXXXX")"
trap 'rm -rf "$d"' EXIT
# spec: README.md "Profiles" -- NSWindowStyleMaskFullSizeContentView is 10.10's; 10.9-targeted code that uses it is told
#       so (fullsize_availability)
SC="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
for c in /usr/local/mavergreen/clang22/bin/clang /usr/local/mavergreen/clang22-cross/bin/clang; do
  [ -x "$c" ] && CLANG22=$c && break
done
win=$(python3 -c 'import json; print([i for i in json.load(open("sdk-metadata/profiles.json"))["profiles"]["swift-appkit"]["recipes"] if i.startswith("appkit-window-")][0])')
ov=$("$SC" -DMODULES="$(dirname "$SHIPYARD_SCRIPTS")" -DSDK="$SDK" -DRECIPES="$PWD/sdk-metadata/recipes.json" -DIDS="$win" \
       -DOUT="$d/fullsize" -P tests/fixtures/sdk-metadata-materialize.cmake 2>&1 | tail -1)
printf '#import <AppKit/AppKit.h>\nNSUInteger f(void) { return NSWindowStyleMaskFullSizeContentView; }\n' >"$d/fs.m"
fs() { "$CLANG22" --no-default-config -fsyntax-only -Werror=unguarded-availability -x objective-c -arch x86_64 \
         -mmacosx-version-min="$1" -isysroot "$SDK" -ivfsoverlay "$ov" "$d/fs.m" >"$d/fs.out" 2>&1; }
if fs 10.9; then echo "FAIL: fullsize_availability: 10.9 code used NSWindowStyleMaskFullSizeContentView unwarned"; exit 1; fi
fs 10.10 || { echo "FAIL: fullsize_availability: 10.10 code cannot use it:"; head -5 "$d/fs.out"; exit 1; }
echo "swift-appkit-availability OK"
