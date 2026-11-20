#!/bin/sh
# platform: host-agnostic -- reads the kext's objects with llvm-nm, against tests/fixtures/kpi-10.9
# spec: README.md "The kernel back-fill kext" -- every name the kext leaves undefined is exported by a 10.9 KPI
#       library its Info.plist names, so kxld resolves it with no com.apple.kpi.private
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/kext.sh
d="$(mktemp -d "${TMPDIR:-/tmp}/kext-imports.XXXXXX")"
trap 'rm -rf "$d"' EXIT
kext_build "$d/k"
set -- "$d"/k/obj/*.o
[ -f "$1" ] || { echo "FAIL: no objects in $d/k/obj"; exit 1; }
"$NM" -m "$@" | awk '!/undefined/ { print $NF }' | LC_ALL=C sort -u > "$d/defined"
# platform: libkmod.a, linked last, supplies _start and _stop (its c_start.o), as symbols __start and __stop
"$NM" -u "$@" | awk 'NF { print $NF }' | grep -v ':$' | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$d/defined" \
  | grep -vx -e __start -e __stop > "$d/undefined" || true
[ -s "$d/undefined" ] || { echo "FAIL: the objects import nothing, so this test checks nothing"; exit 1; }
: > "$d/available"
for l in $(plist "$d/k/RecaulkKPI.kext/Contents/Info.plist" get OSBundleLibraries); do
  f="tests/fixtures/kpi-10.9/${l%%=*}.txt"
  [ -f "$f" ] || { echo "FAIL: no 10.9 export list for ${l%%=*} ($f)"; exit 1; }
  cat "$f" >> "$d/available"
done
LC_ALL=C sort -u -o "$d/available" "$d/available"
missing="$(LC_ALL=C comm -23 "$d/undefined" "$d/available" | tr '\n' ' ')"
[ -z "$missing" ] || { echo "FAIL: imported but no named 10.9 KPI library exports them: $missing"; exit 1; }
