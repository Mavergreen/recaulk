#!/bin/sh
# platform: macOS-only -- nm reads Mach-O symbol tables
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
dylib="$T/lib/libRecaulkSystem.dylib"
fixture=tests/fixtures/libSystemWrapper-exports.txt
fail=0
bad() { echo "FAIL: $*"; fail=1; }

[ "$(wc -l < "$fixture" | tr -d ' ')" = 194 ] \
  || bad "$fixture does not have 194 lines: it is the export list of libSystemWrapper.dylib sha256 173e9b89c1941b6a1caa7c79c4dd015ae2e2117de9aed42f5d925ed70a8362d7; re-extract it, never edit it"

have="$(mktemp "${TMPDIR:-/tmp}/parity.XXXXXX")"
trap 'rm -f "$have"' EXIT
nm -gU "$dylib" | awk '{print $3}' | LC_ALL=C sort -u > "$have"
missing="$(LC_ALL=C comm -23 "$fixture" "$have")"
[ -z "$missing" ] || bad "libRecaulkSystem must export everything Wowfunhappy's libSystemWrapper does (spec, Product 1, parity); missing $(printf '%s\n' "$missing" | wc -l | tr -d ' '): $(printf '%s\n' "$missing" | tr '\n' ' ')"
[ "$fail" = 0 ] && echo "parity OK"
exit $fail
