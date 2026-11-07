#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
. build/lib.sh
B="$(recaulk_build_dir)"
[ -f "$B/stage/usr/local/mavergreen/recaulk/lib/librecaulk.a" ] || { echo "not built: run sh build/build-lib.sh first"; exit 77; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/package-pkg.XXXXXX")"   # template: 10.9 BSD mktemp requires one
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/build"
cp -R "$B/stage" "$tmp/build/stage"
cp "$B/build-tools.txt" "$tmp/build/"

app="$(RECAULK_BUILD="$tmp/build" sh build/build-updater.sh 20261005.1 2>"$tmp/updater.log")" \
  || { cat "$tmp/updater.log"; echo "FAIL: the updater did not build"; exit 1; }
rm -rf "$tmp/app-only"; mkdir "$tmp/app-only"
rc=0; BUILD="$tmp/build" OUT="$tmp/noapp" UPD_APP="$tmp/app-only" VERSION=20261005.1 sh build/package-pkg.sh >/dev/null 2>"$tmp/noapp.err" || rc=$?
[ "$rc" != 0 ] && grep -q 'not a built updater' "$tmp/noapp.err" \
  || { echo "FAIL: an updater .app with no executable was packaged (rc $rc): $(cat "$tmp/noapp.err")"; exit 1; }
pkg="$(BUILD="$tmp/build" UPD_APP="$app" VERSION=20261005.1 sh build/package-pkg.sh 2>"$tmp/pkg.log")" \
  || { cat "$tmp/pkg.log"; echo "FAIL: package-pkg.sh failed"; exit 1; }
[ -f "$pkg" ] || { echo "no pkg produced"; exit 1; }
[ "$(basename "$pkg")" = recaulk-20261005.1.pkg ] || { echo "wrong pkg name: $pkg"; exit 1; }

SD="$(sh "$SHIPYARD_SCRIPTS/fetch_stevedore.sh")"
"$SD" expand "$pkg" "$tmp/x" >/dev/null
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
archive_first="$(ls -d "$tmp"/x/*.pkg | head -1)"
[ "$archive_first" != "$comp" ] || { echo "the product component must not be the archive's first"; exit 1; }
mkdir "$tmp/files"
gzip -dc < "$comp/Payload" > "$tmp/payload.cpio" || { echo "FAIL: the payload does not decompress"; exit 1; }
( cd "$tmp/files" && cpio -id --quiet < "$tmp/payload.cpio" ) || { echo "FAIL: cpio could not extract the payload"; exit 1; }
for f in librecaulk.a librecaulk-cxxabi-exports.a libRecaulkSystem.dylib; do
  cmp -s "$tmp/files/usr/local/mavergreen/recaulk/lib/$f" "$B/stage/usr/local/mavergreen/recaulk/lib/$f" \
    || { echo "FAIL: the packaged $f is not byte-identical to the built and tested one"; exit 1; }
done

FILES="$(cd "$tmp/files" && find . -type f | sed 's|^\./||')"
need() { printf '%s\n' "$FILES" | grep -qx "$1" || { echo "the payload lacks $1"; exit 1; }; }
need 'usr/local/mavergreen/recaulk/lib/librecaulk.a'
need 'usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib'
need 'usr/local/mavergreen/recaulk/include/recaulk/MacportsLegacySupport.h'
need 'usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json'
need 'usr/local/mavergreen/recaulk/mavergreen.plist'
need 'usr/local/mavergreen/recaulk/share/recaulk/notices.tsv'
need 'Library/Application Support/Mavergreen/recaulk-updater.app/Contents/Resources/recaulk-updater.icns'
need 'Library/LaunchAgents/dev.mavergreen.recaulk-updatecheck.plist'
! printf '%s\n' "$FILES" | grep -Eq 'usr/local/mavergreen/legacysupport|usr/local/lib' || { echo "the payload carries the old layout or /usr/local/lib"; exit 1; }

info="$(dirname "$pkg")/build-info-release.txt"
[ -f "$info" ] || { echo "FAIL: no build-info-release.txt beside the pkg"; exit 1; }
for k in clang22 drydock macports-legacy-support build-make updater-cmake updater-build-tool; do
  grep -q "^$k=." "$info" || { echo "FAIL: build-info-release.txt records no $k: $(tr '\n' ' ' < "$info")"; exit 1; }
done
[ "$(sed -n 's/^clang22=//p' "$info")" = "$(tr -d ' \t\n' < components/clang22/version)" ] \
  || { echo "FAIL: build-info's clang22 is not the pinned components/clang22/version"; exit 1; }
echo "package-pkg OK -> $(basename "$pkg")"
