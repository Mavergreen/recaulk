#!/bin/sh
# platform: host-agnostic -- builds the kext's Info.plist from src/kext/Info.plist.in
# spec: README.md "The kernel back-fill kext" -- the interface consumers read: bundle id, a library kext with no
#       personalities, OSBundleCompatibleVersion 1.0.0, and a CFBundleVersion OSKext can parse that orders as
#       Recaulk's releases do (YYYYMMDD.N becomes YYMM.DD.N: OSKext allows at most 4, 2 and 2 digits)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/kext.sh
d="$(mktemp -d "${TMPDIR:-/tmp}/kext-plist.XXXXXX")"
trap 'rm -rf "$d"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
kext_build "$d/a" 20261120.1
p="$d/a/RecaulkKPI.kext/Contents/Info.plist"
[ -f "$p" ] || { echo "FAIL: no $p"; exit 1; }
want() { got="$(plist "$p" get "$1" || echo '<absent>')"; [ "$got" = "$2" ] || bad "$1 is '$got', want '$2'"; }
want CFBundleIdentifier dev.mavergreen.recaulk.kpi
want CFBundleExecutable RecaulkKPI
want CFBundlePackageType KEXT
want OSBundleCompatibleVersion 1.0.0
want CFBundleVersion 2611.20.1
want CFBundleShortVersionString 20261120.1
plist "$p" get IOKitPersonalities >/dev/null 2>&1 && bad "it has IOKitPersonalities; a library kext has none"
kext_build "$d/b" 20261231.12
want2="$(plist "$d/b/RecaulkKPI.kext/Contents/Info.plist" get CFBundleVersion)"
[ "$want2" = 2612.31.12 ] || bad "VERSION 20261231.12 gave CFBundleVersion $want2, want 2612.31.12"
if VERSION=1.2.3 sh build/build-kext.sh "$d/c" > "$d/c.log" 2>&1; then bad "VERSION 1.2.3 was accepted; only YYYYMMDD.N maps onto OSKext's version"; fi
exit $fail
