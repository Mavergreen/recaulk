#!/bin/sh
# platform: macOS-only -- pkgutil/lsbom/cpio inspect the built .pkg, and the updater is a Cocoa build
set -eu
cd "$(dirname "$0")/.."
SC="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"; [ -x "$SC" ] || { echo "no shipyard-cmake -- skipping" >&2; exit 77; }
. build/msc.sh || { echo "msc.sh could not locate shipyard -- skipping" >&2; exit 77; }
[ -f "$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake" ] \
  || { echo "the shipyard at $SHIPYARD_SCRIPTS predates MavericksToolchain.cmake -- install the current shipyard pkg" >&2; exit 1; }
. build/lib.sh
B="$(recaulk_build_dir)"
[ -f "$B/stage/usr/local/mavergreen/recaulk/lib/librecaulk.a" ] || { echo "not built: run sh build/build-lib.sh first"; exit 77; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/package-pkg.XXXXXX")"   # template: 10.9 BSD mktemp requires one
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/build"
cp -R "$B/stage" "$tmp/build/stage"

"$SC" -S . -B "$tmp/updater" -DCMAKE_OBJC_COMPILER=/usr/bin/clang -DRECAULK_VERSION=20261005.1 \
  -DCMAKE_TOOLCHAIN_FILE="$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake" >/dev/null
"$SC" --build "$tmp/updater" --target recaulk-updater >/dev/null

pkg="$(BUILD="$tmp/build" UPD_APP="$tmp/updater/recaulk-updater.app" VERSION=20261005.1 sh build/package-pkg.sh)"
[ -f "$pkg" ] || { echo "no pkg produced"; exit 1; }
[ "$(basename "$pkg")" = recaulk-20261005.1.pkg ] || { echo "wrong pkg name: $pkg"; exit 1; }

pkgutil --expand "$pkg" "$tmp/x"
grep -q 'os-version min="10.9.5"' "$tmp/x/Distribution" || { echo "10.9.5 floor missing"; exit 1; }
first="$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$tmp/x/Distribution" | grep -v '^default$' | head -1)"
[ "$first" = dev.mavergreen.base ] || { echo "the base component must come first, got $first"; exit 1; }

comp=""
for d in "$tmp"/x/*.pkg; do
  [ -f "$d/PackageInfo" ] || continue
  if grep -q 'identifier="dev.mavergreen.recaulk"' "$d/PackageInfo"; then comp="$d"; fi
done
[ -n "$comp" ] || { echo "no component with identifier dev.mavergreen.recaulk"; exit 1; }
[ -f "$comp/Payload" ] || { echo "component has no Payload"; exit 1; }
mkdir "$tmp/files"
( cd "$tmp/files" && gzip -dc "$comp/Payload" | cpio -id 2>/dev/null )
[ -f "$tmp/files/usr/local/mavergreen/recaulk/lib/librecaulk.a" ] || { echo "extraction lacks librecaulk.a"; exit 1; }
[ -f "$tmp/files/usr/local/mavergreen/recaulk/include/recaulk/MacportsLegacySupport.h" ] || { echo "extraction lacks the header"; exit 1; }
archive_first="$(ls -d "$tmp"/x/*.pkg | head -1)"
[ "$archive_first" != "$comp" ] || { echo "the product component must not be the archive's first"; exit 1; }

BOM="$(lsbom "$comp/Bom")"
need() { printf '%s\n' "$BOM" | grep -q "$1" || { echo "BOM lacks $1"; exit 1; }; }
need 'usr/local/mavergreen/recaulk/lib/librecaulk.a'
need 'usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib'
need 'usr/local/mavergreen/recaulk/include/recaulk/MacportsLegacySupport.h'
need 'usr/local/mavergreen/recaulk/mavergreen.plist'
need 'Library/Application Support/Mavergreen/recaulk-updater.app/Contents/Resources/recaulk-updater.icns'
need 'Library/LaunchAgents/dev.mavergreen.recaulk-updatecheck.plist'
! printf '%s\n' "$BOM" | grep -Eq 'usr/local/mavergreen/legacysupport|usr/local/lib' || { echo "the BOM carries the old layout or /usr/local/lib"; exit 1; }
echo "package-pkg OK -> $(basename "$pkg")"
