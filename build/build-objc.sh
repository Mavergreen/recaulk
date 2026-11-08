#!/bin/sh
# platform: host-agnostic
#   usage: build-objc.sh STAGE_PREFIX WORK_DIR [--native-test]
#          builds the separate Objective-C provider archive with clang22 and stages lib/librecaulk-objc.a and
#          share/recaulk/objc-providers.json, plus share/recaulk/objc-source.receipt for a shipping stage.
#          --native-test builds for this Mac's own arch instead.
set -eu
umask 022
SELF=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
. "$SELF/lib.sh"
ROOT=$MAVERICKS_ROOT
[ "$#" = 2 ] || [ "$#" = 3 ] || { sed -n 3p "$0" >&2; exit 2; }
T=$1; W=$2
case "$T:$W" in /*:/*) ;; *) echo 'build-objc: absolute stage/work paths required' >&2; exit 2 ;; esac
arch=x86_64; floor=10.9; role=shipping
if [ "$#" = 3 ]; then
  [ "$3" = --native-test ] || exit 2
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64) arch=arm64; floor=11.0 ;;
    Darwin:x86_64) ;;
    *) echo 'build-objc: --native-test builds for the Mac it runs on' >&2; exit 2 ;;
  esac
  role=native-test-only
fi
[ -n "${SDK:-}" ] || SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
[ -f "$SDK/SDKSettings.plist" ] || { echo "build-objc: $SDK is not an SDK" >&2; exit 1; }
recaulk_tools
TARGET_FLAGS="--no-default-config --target=$arch-apple-macos$floor -mmacosx-version-min=$floor"
export CC TARGET_FLAGS SDK LIPO
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
mkdir -p "$W/objects" "$W/generated" "$T/lib" "$T/share/recaulk"
"$CC" --version > "$W/compiler.txt"
printf 'SDK=%s\n' "$SDK" > "$W/sdk.txt"
G="$SELF/objc-provider-manifest.sh"; D="$ROOT/src/objc/providers.json"
sh "$G" header "$D" "$W/generated/providers-generated.h"
# spec: tests/objc-archive-reproducible.sh -- the prefix maps make every checkout and work directory build the same
#       bytes, and name each source by the relative label source-inputs.txt records (the receipt's labels)
# spec: tests/objc-source-receipt.sh -- -g keeps each member's line table, which the source receipt maps sends through
for f in workspace workspace-events workspace-recents register; do
  "$CC" $TARGET_FLAGS -isysroot "$SDK" -fno-objc-arc -Os -g -fPIC -Wall -Wno-deprecated-declarations \
    -ffile-prefix-map="$ROOT/"= -ffile-prefix-map="$W/"= \
    -ffile-prefix-map="$SDK"="$(basename "$SDK")" -fdebug-compilation-dir=. \
    -I"$W/generated" -c "$ROOT/src/objc/$f.m" -o "$W/objects/$f.o"
done
recaulk_archive "$W/librecaulk-objc.a" "$W/objects/workspace.o" "$W/objects/workspace-events.o" \
  "$W/objects/workspace-recents.o" "$W/objects/register.o"
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
(cd "$ROOT" && sha256 src/objc/workspace.m src/objc/workspace-events.m src/objc/workspace-recents.m \
  src/objc/register.m src/objc/workspace-private.h src/objc/providers.json build/build-objc.sh \
  build/objc-provider-manifest.sh) > "$W/source-inputs.txt"
(cd "$W" && sha256 generated/providers-generated.h) >> "$W/source-inputs.txt"
sh "$G" manifest "$D" "$W/librecaulk-objc.a" "$W/objc-providers.json" "$arch" "$role" \
  "$SDK/SDKSettings.plist" "$W/compiler.txt" "$W/source-inputs.txt"
rm -f "$W/objc-source.receipt"
# spec: tests/objc-source-receipt.sh -- every shipping stage carries the receipt. shipyard's objc-source-inventory.sh
#   (v1.0.727 and later) runs on Linux and a Mac and fetches its own pinned clang22 unless given one.
if [ "$role" = shipping ]; then
  [ -f "$SHIPYARD_SCRIPTS/objc-source-inventory.sh" ] ||
    { echo "build-objc: $SHIPYARD_SCRIPTS has no objc-source-inventory.sh to write the source receipt (shipyard v1.0.727+)" >&2; exit 1; }
  set --
  [ -z "${MAVERICKS_OBJC_CLANG_PREFIX:-}" ] || set -- --clang-prefix "$MAVERICKS_OBJC_CLANG_PREFIX"
  sh "$SHIPYARD_SCRIPTS/objc-source-inventory.sh" "$@" --inputs "$W/source-inputs.txt" \
    --root "$ROOT" --root "$W" --unit src/objc/workspace.m --unit src/objc/workspace-events.m \
    --unit src/objc/workspace-recents.m --unit src/objc/register.m --include generated \
    --output "$W/objc-source.receipt"
fi
# spec: tests/objc-provider-symbols.sh -- a declared implementation the analyzer could not resolve fails the build,
#       before anything reaches the stage
sh "$SELF/check-objc-impls.sh" "$W/objc-providers.json" "$W/librecaulk-objc.a"
cp "$W/librecaulk-objc.a" "$T/lib/librecaulk-objc.a"
cp "$W/objc-providers.json" "$T/share/recaulk/objc-providers.json"
if [ -f "$W/objc-source.receipt" ]; then cp "$W/objc-source.receipt" "$T/share/recaulk/objc-source.receipt"
else rm -f "$T/share/recaulk/objc-source.receipt"; fi
printf '%s\n' "$T"
