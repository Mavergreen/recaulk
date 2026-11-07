#!/bin/sh
# platform: macOS-only -- separate Apple-compiler archive; never modifies C libraries
set -eu
umask 022
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
[ "$#" = 2 ] || [ "$#" = 3 ] || { echo 'usage: build-objc.sh STAGE_PREFIX WORK_DIR [--native-test]' >&2; exit 2; }
T=$1; W=$2
case "$T:$W" in /*:/*) ;; *) echo 'build-objc: absolute stage/work paths required' >&2; exit 2 ;; esac
: "${SHIPYARD_SCRIPTS:?set pinned shipyard scripts}"
case "$(uname -m)" in arm64) host=arm64; hostfloor=11.0 ;; x86_64) host=x86_64; hostfloor=10.9 ;; *) exit 1 ;; esac
arch=x86_64; floor=10.9; role=shipping
if [ "$#" = 3 ]; then
 [ "$3" = --native-test ] || exit 2
 arch=$host; floor=$hostfloor; role=native-test-only
fi
if [ -z "${SDK:-}" ]; then SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch"); fi
if [ -z "${HOST_SDK:-}" ]; then HOST_SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$host"); fi
[ -f "$SDK/SDKSettings.plist" ] && [ -f "$HOST_SDK/SDKSettings.plist" ] || { echo 'build-objc: valid target/host SDKs required' >&2; exit 1; }
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
mkdir -p "$W/objects" "$W/generated" "$T/lib" "$T/share/recaulk"
/usr/bin/clang --version > "$W/compiler.txt"
/usr/bin/clang -arch "$host" -isysroot "$HOST_SDK" -mmacosx-version-min="$hostfloor" -fno-objc-arc -Wno-deprecated-declarations "$ROOT/build/objc-provider-manifest.m" -o "$W/objc-provider-manifest" -framework Foundation
G="$W/objc-provider-manifest"; D="$ROOT/src/objc/providers.json"
"$G" header "$D" "$W/generated/providers-generated.h"
# -g keeps each member's line table: shipyard maps the archive's message sends to the
# prepared source through it (its objc source receipt). Code generation is unchanged.
for f in workspace workspace-events workspace-recents register; do
 /usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Os -g -fPIC -Wall -Wno-deprecated-declarations -I"$W/generated" -c "$ROOT/src/objc/$f.m" -o "$W/objects/$f.o"
done
/usr/bin/libtool -static -o "$W/librecaulk-objc.a" "$W/objects/workspace.o" "$W/objects/workspace-events.o" "$W/objects/workspace-recents.o" "$W/objects/register.o"
(cd "$ROOT" && shasum -a 256 src/objc/workspace.m src/objc/workspace-events.m src/objc/workspace-recents.m src/objc/register.m src/objc/workspace-private.h src/objc/providers.json build/build-objc.sh build/objc-provider-manifest.m) > "$W/source-inputs.txt"
(cd "$W" && shasum -a 256 generated/providers-generated.h) >> "$W/source-inputs.txt"
"$G" manifest "$D" "$W/librecaulk-objc.a" "$W/objc-providers.json" "$arch" "$role" "$SDK/SDKSettings.plist" "$W/compiler.txt" "$W/source-inputs.txt"
# A shipping stage also carries the provider body's source receipt: shipyard's
# objc-source-inventory.sh over exactly the prepared source above, parsed by the
# pinned clang (shipyard's components/objc-reference-clang/version, or an
# extracted one named by MAVERICKS_OBJC_CLANG_PREFIX). A consumer's analysis
# closes the body's own sends only through it.
rm -f "$W/objc-source.receipt"
if [ "$role" = shipping ]; then
 CLANG=${MAVERICKS_OBJC_CLANG_PREFIX:-}
 if [ -z "$CLANG" ]; then
  case "$host" in x86_64) short=clang22; flavor=native ;; *) short=clang22-cross; flavor=cross ;; esac
  version=$(tr -d '[:space:]' < "$SHIPYARD_SCRIPTS/../components/objc-reference-clang/version")
  CLANG=$(sh "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" --asset "mavericks-clang-22-$flavor-$version.pkg" "$short" "$version" "$W/objc-reference-$short-$version")
 fi
 sh "$SHIPYARD_SCRIPTS/objc-source-inventory.sh" --clang-prefix "$CLANG" --inputs "$W/source-inputs.txt" \
  --root "$ROOT" --root "$W" --unit src/objc/workspace.m --unit src/objc/workspace-events.m \
  --unit src/objc/workspace-recents.m --unit src/objc/register.m --include generated --output "$W/objc-source.receipt"
fi
# Stage only a completed matching set; failures above leave prior outputs alone.
cp "$W/librecaulk-objc.a" "$T/lib/librecaulk-objc.a"
cp "$W/objc-providers.json" "$T/share/recaulk/objc-providers.json"
if [ -f "$W/objc-source.receipt" ]; then cp "$W/objc-source.receipt" "$T/share/recaulk/objc-source.receipt"
else rm -f "$T/share/recaulk/objc-source.receipt"; fi
printf '%s\n' "$T"
