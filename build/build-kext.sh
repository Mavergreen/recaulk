#!/bin/sh
# platform: host-agnostic -- compiles with clang22 against the 10.9 SDK's Kernel.framework on any host; links
#           only with an ld64 that writes MH_KEXT_BUNDLE (RECAULK_KEXT_LD), which no family toolchain ships yet
# spec: README.md "The kernel back-fill kext"
# usage: VERSION=YYYYMMDD.N sh build/build-kext.sh OUT
#   OUT/obj/*.o                         the objects
#   OUT/RecaulkKPI.kext/Contents/Info.plist
#   OUT/RecaulkKPI.kext/Contents/MacOS/RecaulkKPI   only when RECAULK_KEXT_LD names a linker
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"
OUT="${1:?usage: VERSION=YYYYMMDD.N sh build/build-kext.sh OUT}"
: "${VERSION:?build-kext: VERSION (YYYYMMDD.N) required}"
# spec: README.md "The kernel back-fill kext" -- OSKext parses CFBundleVersion as at most 4, 2 and 2 digits
#       (xnu-2422.115.4 libkern/OSKextVersion.c), so YYYYMMDD.N becomes YYMM.DD.N, which orders the same
bundle_version="$(printf '%s\n' "$VERSION" | sed -n 's/^20\([0-9][0-9]\)\([01][0-9]\)\([0-3][0-9]\)\.\([1-9][0-9]\{0,1\}\)$/\1\2.\3.\4/p' | sed 's/^0*//; s/\.0\([0-9]\)\./.\1./')"
[ -n "$bundle_version" ] || { echo "build-kext: VERSION '$VERSION' is not YYYYMMDD.N (N 1-99, a 21st-century date)" >&2; exit 1; }
if [ -z "${SDK:-}" ]; then
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
fi
recaulk_tools
KH="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
[ -d "$KH" ] || { echo "build-kext: the SDK has no Kernel.framework headers ($KH)" >&2; exit 1; }
SRC="$MAVERICKS_ROOT/src/kext"
K="$OUT/RecaulkKPI.kext"
rm -rf "$OUT/obj" "$K"
mkdir -p "$OUT/obj" "$K/Contents/MacOS"
# platform: --no-default-config keeps clang.cfg's userland inputs (librecaulk.a, frameworks, Recaulk's headers)
#           out of a kext; -fvisibility=hidden leaves exported only what says so
for c in "$SRC"/*.c; do
  "$CC" $TARGET_FLAGS -isysroot "$SDK" -mkernel -nostdinc -fno-builtin -fno-common -fvisibility=hidden \
    -I"$KH" -DKERNEL -D__APPLE_CC__=6000 -DRECAULK_KPI_VERSION="\"$bundle_version\"" \
    -Wall -Wextra -Werror -O2 -c "$c" -o "$OUT/obj/$(basename "$c" .c).o"
done
sed -e "s/@RELEASE@/$VERSION/" -e "s/@BUNDLE_VERSION@/$bundle_version/" "$SRC/Info.plist.in" > "$K/Contents/Info.plist"
if [ -z "${RECAULK_KEXT_LD:-}" ]; then
  rmdir "$K/Contents/MacOS"
  echo "build-kext: compiled $OUT/obj; not linked: no family linker writes MH_KEXT_BUNDLE yet (Mavergreen cctools);" \
    "set RECAULK_KEXT_LD to an ld64 with -kext to link" >&2
  exit 0
fi
"$RECAULK_KEXT_LD" -arch x86_64 -macosx_version_min 10.9 -kext -L"$SDK/usr/lib" "$OUT"/obj/*.o -lkmod \
  -o "$K/Contents/MacOS/RecaulkKPI"
