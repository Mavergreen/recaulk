#!/bin/sh
# platform: host-agnostic -- compiles with clang22 against the 10.9 SDK's Kernel.framework, and links with Mavergreen
#           cctools' ld64 -kext (the one family linker that writes MH_KEXT_BUNDLE), on any host
# spec: README.md "The kernel back-fill kext"
# usage: VERSION=YYYYMMDD.N sh build/build-kext.sh OUT
#   OUT/obj/*.o                         the objects
#   OUT/RecaulkKPI.kext/Contents/Info.plist
#   OUT/RecaulkKPI.kext/Contents/MacOS/RecaulkKPI
# RECAULK_KEXT_LD names another ld64 to link with; unset, components/cctools/version's is fetched into OUT/tools
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
LD="${RECAULK_KEXT_LD:-}"
if [ -z "$LD" ]; then
  LD="$(sh "$SELF/fetch-cctools.sh" "$OUT/tools")/bin/ld"
fi
# spec: README.md "The kernel back-fill kext" -- ld64 -kext writes MH_KEXT_BUNDLE, which 10.9's kxld loads; ld64.lld
#       cannot. -nostdlib keeps libSystem out; libkmod supplies _kmod_info's start and stop glue.
"$CC" $TARGET_FLAGS -isysroot "$SDK" -nostdlib -fuse-ld=ld --ld-path="$LD" -Wl,-kext -L"$SDK/usr/lib" \
  "$OUT"/obj/*.o -lkmod -o "$K/Contents/MacOS/RecaulkKPI"
