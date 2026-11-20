#!/bin/sh
# platform: host-agnostic -- reads the kext's Info.plist
# spec: README.md "The kernel back-fill kext" -- RecaulkKPI.kext depends only on public KPIs: no
#       com.apple.kpi.private, nothing outside com.apple.kpi.*, each at 13.0.0 (10.9)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/kext.sh
d="$(mktemp -d "${TMPDIR:-/tmp}/kext-libs.XXXXXX")"
trap 'rm -rf "$d"' EXIT
fail=0
kext_build "$d/k"
libs="$(plist "$d/k/RecaulkKPI.kext/Contents/Info.plist" get OSBundleLibraries || true)"
[ -n "$libs" ] || { echo "FAIL: no OSBundleLibraries"; exit 1; }
for l in $libs; do
  id="${l%%=*}"; v="${l#*=}"
  case "$id" in
    com.apple.kpi.private) echo "FAIL: it names com.apple.kpi.private, which only Apple's kexts may link"; fail=1 ;;
    com.apple.kpi.*) ;;
    *) echo "FAIL: it names $id, outside com.apple.kpi"; fail=1 ;;
  esac
  [ "$v" = 13.0.0 ] || { echo "FAIL: $id is at $v, want 13.0.0"; fail=1; }
done
exit $fail
