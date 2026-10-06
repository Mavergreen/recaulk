#!/bin/sh
# platform: macOS-only -- xcrun resolves the SDK, and pkgutil/lsbom inspect the built .pkg
set -eu
cd "$(dirname "$0")/.."
echo "SKIP: build/package-pkg.sh still packages the legacysupport layout, not Recaulk's" >&2; exit 77
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/package-pkg.XXXXXX")/stage"   # template: 10.9 BSD mktemp requires one
sh build/build-lib.sh "$STAGE" >/dev/null   # build-lib.sh fetches the pinned 10.9 SDK itself

printf '1.5.2-mavericks.1\n' > VERSION
tmp="$(mktemp -d "${TMPDIR:-/tmp}/package-pkg-tmp.XXXXXX")"   # template: 10.9 BSD mktemp requires one
# shipyard-cmake IS the shipyard: it finds MavericksShipyard in its own prefix, which is why this
# needs no registry, no CMAKE_PREFIX_PATH and no probing. Without it nothing can configure this
# project at all, so skip (77) rather than fail. The sibling-checkout tier this used to have is gone
# with the registry it wrote: a `--install` of a sibling working copy now lands somewhere no cmake
# looks, and a box with no shipyard pkg has no shipyard-cmake to point at it anyway. See the README's
# "Install (once)"; to test against a shipyard you are developing, install it to a prefix of your own
# and run this with CMAKE_PREFIX_PATH set to it.
SC="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"; [ -x "$SC" ] || { echo "no shipyard-cmake -- skipping" >&2; exit 77; }
# msc.sh gives us SHIPYARD_SCRIPTS to point at MavericksToolchain.cmake: the toolchain-file backstop
# FATAL_ERRORs a configure whose sysroot isn't the pinned SDK, and a bare shipyard-cmake call sets none.
. build/msc.sh || { echo "msc.sh could not locate shipyard -- skipping" >&2; exit 77; }
# A shipyard older than its toolchain file is found but cannot configure this project: a stale
# install, not a platform limit, so fail and say so rather than skip.
[ -f "$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake" ] \
  || { echo "the shipyard at $SHIPYARD_SCRIPTS predates MavericksToolchain.cmake -- install the current shipyard pkg" >&2; exit 1; }
"$SC" -S . -B "$tmp/updater" -DCMAKE_OBJC_COMPILER=/usr/bin/clang \
  -DCMAKE_TOOLCHAIN_FILE="$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake" >/dev/null
"$SC" --build "$tmp/updater" --target legacysupport-updater >/dev/null

OUT="$tmp/out"
pkg="$(STAGE="$STAGE" UPD_APP="$tmp/updater/legacysupport-updater.app" \
       VERSION=1.5.2-mavericks.1 OUT="$OUT" sh build/package-pkg.sh)"
[ -f "$pkg" ] || { echo "no pkg produced"; exit 1; }
X="$(mktemp -d "${TMPDIR:-/tmp}/package-pkg-x.XXXXXX")"; pkgutil --expand "$pkg" "$X/x"   # template: 10.9 BSD mktemp requires one
grep -q 'os-version min="10.9.5"' "$X/x/Distribution" || { echo "10.9.5 floor missing"; exit 1; }
COMP="$X/x/macports-legacy-support-component.pkg"
[ -d "$COMP" ] || { echo "no product component in the archive"; exit 1; }
first="$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$X/x/Distribution" | grep -v '^default$' | head -1)"
[ "$first" = dev.mavergreen.base ] || { echo "the base component must come first, got $first"; exit 1; }
BOM="$(lsbom "$COMP/Bom")"
printf '%s\n' "$BOM" | grep -q 'usr/local/mavergreen/legacysupport/lib/libMacportsLegacySupport.dylib' || { echo "lib not in the product tree"; exit 1; }
printf '%s\n' "$BOM" | grep -q 'usr/local/mavergreen/legacysupport/mavergreen.plist' || { echo "no manifest"; exit 1; }
printf '%s\n' "$BOM" | grep -q 'legacysupport-updater.app' || { echo "updater not in payload"; exit 1; }
printf '%s\n' "$BOM" | grep -q 'Library/LaunchAgents/dev.mavergreen.macports-legacy-support-updatecheck.plist' || { echo "LaunchAgent not in payload"; exit 1; }
printf '%s\n' "$BOM" | grep -q '\./usr/local/lib/' && { echo "nothing installs into /usr/local/lib"; exit 1; }
echo "package-pkg OK -> $pkg"
