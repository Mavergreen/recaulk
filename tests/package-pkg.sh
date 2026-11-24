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
need 'usr/local/mavergreen/recaulk/share/sdk-metadata/profiles.json'
# spec: .superpowers/specs/2026-11-24-recaulk-materialize-design.md "Delivery" -- the materializer beside the recipes it
#       reads: universal where the compiler can target arm64 (every release build), and it finds ../share/sdk-metadata
need 'usr/local/mavergreen/recaulk/bin/recaulk-materialize'
RM="$tmp/files/usr/local/mavergreen/recaulk/bin/recaulk-materialize"
[ "$(cpio -itv < "$tmp/payload.cpio" 2>/dev/null | grep 'bin/recaulk-materialize$' | cut -c1-10)" = -rwxr-xr-x ] \
  || { echo "FAIL: bin/recaulk-materialize is not 0755 in the payload"; exit 1; }
recaulk_tools
archs="$("$LIPO" -archs "$RM")"
case " $archs " in *" x86_64 "*) ;; *) echo "FAIL: recaulk-materialize has no x86_64 slice: $archs"; exit 1 ;; esac
if "$CL/bin/clang" --print-targets 2>/dev/null | grep -q aarch64; then
  case " $archs " in *" arm64 "*) ;; *) echo "FAIL: recaulk-materialize has no arm64 slice: $archs"; exit 1 ;; esac
fi
if [ "$(uname -s)" = Darwin ]; then
  "$RM" --print-stamp --profile swift-foundation >/dev/null \
    || { echo "FAIL: the packaged recaulk-materialize does not find its share/sdk-metadata"; exit 1; }
fi
# platform: the pkg installs as root, and mktemp -d makes 0700 directories: 20261107.2 shipped
#           share/sdk-metadata 0700 root, which no product build could read
modes="$(cpio -itv < "$tmp/payload.cpio" 2>/dev/null | grep 'share/sdk-metadata' | cut -c1-10 | tr '\n' ' ')"
[ "$modes" = "drwxr-xr-x -rw-r--r-- -rw-r--r-- " ] || { echo "FAIL: share/sdk-metadata is not world-readable in the payload: $modes"; exit 1; }
need 'usr/local/mavergreen/recaulk/mavergreen.plist'
need 'usr/local/mavergreen/recaulk/share/recaulk/notices.tsv'
need 'usr/local/mavergreen/recaulk/share/recaulk/unexported-symbols.txt'
need 'usr/local/mavergreen/recaulk/share/recaulk/image-local-shadows.txt'
need 'usr/local/mavergreen/recaulk/share/recaulk/system-overrides.txt'
need 'Library/Application Support/Mavergreen/recaulk-updater.app/Contents/Resources/recaulk-updater.icns'
need 'Library/LaunchAgents/dev.mavergreen.recaulk-updatecheck.plist'
# spec: README.md "The kernel back-fill kext" -- the pkg installs RecaulkKPI.kext where 10.9 loads third-party kexts,
#       root-owned and writable only by root (kextd refuses anything else), with this release as CFBundleVersion
need 'Library/Extensions/RecaulkKPI.kext/Contents/Info.plist'
need 'Library/Extensions/RecaulkKPI.kext/Contents/MacOS/RecaulkKPI'
# platform: -n prints ids, since Linux's group database names gid 0 root where 10.9's names it wheel
kmodes="$(cpio -itvn < "$tmp/payload.cpio" 2>/dev/null | grep 'Library/Extensions/RecaulkKPI.kext' | awk '{ print $1, $3, $4, $NF }' | LC_ALL=C sort -k4)"
printf '%s\n' "$kmodes" | awk '$2 != "0" || $3 != "0" { bad = 1 } END { exit bad }' \
  || { echo "FAIL: the kext is not root:wheel in the payload: $kmodes"; exit 1; }
printf '%s\n' "$kmodes" | awk '$1 ~ /^.....w/ || $1 ~ /^........w/ { bad = 1 } END { exit bad }' \
  || { echo "FAIL: the kext has a group- or world-writable entry in the payload: $kmodes"; exit 1; }
kver="$(sed -n '/<key>CFBundleVersion<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$tmp/files/Library/Extensions/RecaulkKPI.kext/Contents/Info.plist")"
[ "$kver" = 2610.5.1 ] || { echo "FAIL: the packaged kext's CFBundleVersion is '$kver', not 2610.5.1 (release 20261005.1)"; exit 1; }
grep -q 'Library/Extensions/RecaulkKPI.kext' "$tmp/files/usr/local/mavergreen/recaulk/mavergreen.plist" \
  || { echo "FAIL: the manifest's outside list lacks the kext, so uninstall would leave it"; exit 1; }
# spec: README.md "The kernel-fixes kext" -- RecaulkKernelFixes.kext beside RecaulkKPI, root-owned and writable only by
#       root, with the LaunchDaemon that loads it at boot; uninstall removes both
need 'Library/Extensions/RecaulkKernelFixes.kext/Contents/Info.plist'
need 'Library/Extensions/RecaulkKernelFixes.kext/Contents/MacOS/RecaulkKernelFixes'
need 'Library/LaunchDaemons/dev.mavergreen.recaulk.kernelfixes.plist'
fmodes="$(cpio -itvn < "$tmp/payload.cpio" 2>/dev/null | grep -e 'Library/Extensions/RecaulkKernelFixes.kext' -e 'dev.mavergreen.recaulk.kernelfixes.plist' | awk '{ print $1, $3, $4, $NF }')"
printf '%s\n' "$fmodes" | awk '$2 != "0" || $3 != "0" || $1 ~ /^.....w/ || $1 ~ /^........w/ { bad = 1 } END { exit bad }' \
  || { echo "FAIL: the kernel-fixes kext or its daemon is not root:wheel and root-writable only: $fmodes"; exit 1; }
for o in Library/Extensions/RecaulkKernelFixes.kext Library/LaunchDaemons/dev.mavergreen.recaulk.kernelfixes.plist; do
  grep -q "$o" "$tmp/files/usr/local/mavergreen/recaulk/mavergreen.plist" \
    || { echo "FAIL: the manifest's outside list lacks $o, so uninstall would leave it"; exit 1; }
done
# spec: README.md "The kernel back-fill kext" -- the postinstall rebuilds the kext caches, only on the boot volume
post="$(cat "$tmp"/x/*.pkg/Scripts/postinstall 2>/dev/null || :)"
[ -z "$post" ] && post="$(for s in "$tmp"/x/*.pkg/Scripts; do [ -d "$s" ] && (cd "$s" && cat postinstall 2>/dev/null); done)"
printf '%s\n' "$post" | awk '/if \[ -z "\$ROOT" \]/ { on = 1 } on && /kextcache -system-caches/ { ok = 1 } /^fi/ { on = 0 } END { exit !ok }' \
  || { echo "FAIL: the postinstall does not run kextcache -system-caches inside if [ -z \"\$ROOT\" ]"; exit 1; }
! printf '%s\n' "$FILES" | grep -Eq 'usr/local/mavergreen/legacysupport|usr/local/lib' || { echo "the payload carries the old layout or /usr/local/lib"; exit 1; }

info="$(dirname "$pkg")/build-info-release.txt"
[ -f "$info" ] || { echo "FAIL: no build-info-release.txt beside the pkg"; exit 1; }
for k in clang22 cctools drydock macports-legacy-support build-make updater-cmake updater-build-tool; do
  grep -q "^$k=." "$info" || { echo "FAIL: build-info-release.txt records no $k: $(tr '\n' ' ' < "$info")"; exit 1; }
done
[ "$(sed -n 's/^clang22=//p' "$info")" = "$(tr -d ' \t\n' < components/clang22/version)" ] \
  || { echo "FAIL: build-info's clang22 is not the pinned components/clang22/version"; exit 1; }
echo "package-pkg OK -> $(basename "$pkg")"
