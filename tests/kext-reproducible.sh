#!/bin/sh
# platform: host-agnostic -- builds RecaulkKPI.kext twice, from two work directories
# spec: README.md "The kernel back-fill kext" -- the bundle's bytes depend only on the source, the version and the
#       pinned clang22, SDK and cctools: two builds in different directories are identical, LC_UUID (ld64's hash of
#       the content) included
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/kext.sh
d="$(mktemp -d "${TMPDIR:-/tmp}/kext-repro.XXXXXX")"
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/one" "$d/two/deeper"
kext_build "$d/one/k" 20261121.7
kext_build "$d/two/deeper/k" 20261121.7
fail=0
for f in Contents/Info.plist Contents/MacOS/RecaulkKPI; do
  [ -f "$d/one/k/RecaulkKPI.kext/$f" ] || { echo "FAIL: the build made no $f"; fail=1; continue; }
  cmp -s "$d/one/k/RecaulkKPI.kext/$f" "$d/two/deeper/k/RecaulkKPI.kext/$f" || { echo "FAIL: $f differs between two builds"; fail=1; }
done
"$OTOOL" -l "$d/one/k/RecaulkKPI.kext/Contents/MacOS/RecaulkKPI" | grep -q LC_UUID \
  || { echo "FAIL: the binary has no LC_UUID, so a panic would not symbolicate"; fail=1; }
[ "$fail" = 0 ] && echo "kext-reproducible OK"
exit $fail
