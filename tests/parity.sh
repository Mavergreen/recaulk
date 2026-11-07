#!/bin/sh
# platform: host-agnostic -- nm reads Mach-O symbol tables
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
trap 'rm -f "$have" "$have.entries"' EXIT
"$NM" -gU "$dylib" | awk '{print $3}' | LC_ALL=C sort -u > "$have"
missing="$(LC_ALL=C comm -23 "$fixture" "$have")"
[ -z "$missing" ] || bad "libRecaulkSystem must export everything Wowfunhappy's libSystemWrapper does (spec, Product 1, parity); missing $(printf '%s\n' "$missing" | wc -l | tr -d ' '): $(printf '%s\n' "$missing" | tr '\n' ' ')"
# spec: build/header-entries.txt -- the one exception: the names Recaulk's headers give its fixes' 10.9 names
grep -v '^#' build/header-entries.txt | awk 'NF' | LC_ALL=C sort > "$have.entries"
leaked="$(grep '^___recaulk_' "$have" | LC_ALL=C sort | LC_ALL=C comm -23 - "$have.entries" | tr '\n' ' ' || true)"
[ -z "$leaked" ] || bad "libRecaulkSystem exports forwarding-layer internals (no ___recaulk_ name but build/header-entries.txt's may be exported: the impls, slots and resolver are private to the layer): $leaked"
missing="$(grep '^___recaulk_' "$have" | LC_ALL=C sort | LC_ALL=C comm -13 - "$have.entries" | tr '\n' ' ' || true)"
[ -z "$missing" ] || bad "libRecaulkSystem does not export what Recaulk's headers name (build/header-entries.txt): $missing"
[ "$fail" = 0 ] && echo "parity OK"
exit $fail
