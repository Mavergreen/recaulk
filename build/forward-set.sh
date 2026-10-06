#!/bin/sh
# platform: macOS-only -- nm of Mach-O archives
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/sdk-exports.sh"
[ $# -ge 2 ] || { echo "usage: sh build/forward-set.sh SDK ARCHIVE... -- prints the forwarded set, one Mach-O name per line" >&2; exit 2; }
sdk="$1"; shift
tmp="$(mktemp -d "${TMPDIR:-/tmp}/forward-set.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
"${NM:-nm}" -gU "$@" > "$tmp/nm" || { echo "forward-set: nm failed on $*" >&2; exit 1; }
sdk_exports "$sdk" > "$tmp/sdk"
[ -s "$tmp/sdk" ] || { echo "forward-set: no exports read from the SDK at $sdk" >&2; exit 1; }
"${NM:-nm}" -m "$@" > "$tmp/nm-m" || { echo "forward-set: nm -m failed on $*" >&2; exit 1; }
awk '/private external/ { print $NF }' "$tmp/nm-m" | LC_ALL=C sort -u > "$tmp/pext"
awk 'NF == 3 && $2 == "T" { print $3 }' "$tmp/nm" | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$tmp/pext" > "$tmp/T"
LC_ALL=C comm -23 "$tmp/T" "$tmp/sdk" | awk '!/\.eh$/ && !/^___recaulk_/' > "$tmp/F0"
awk '
  NR == FNR {
    if (NF != 3 || ($3 != "private" && $3 != "abi" && $3 != "data")) {
      print "forward-set: " FILENAME ": not \"prefix P WHY\" or \"name N WHY\" (WHY: private, abi or data): " $0 > "/dev/stderr"; bad = 1; exit 1
    }
    if ($1 == "prefix") pre[++np] = $2
    else if ($1 == "name") ex[$2] = 1
    else { print "forward-set: " FILENAME ": not \"prefix P WHY\" or \"name N WHY\": " $0 > "/dev/stderr"; bad = 1; exit 1 }
    next
  }
  { if ($0 in ex) next; for (i = 1; i <= np; i++) if (index($0, pre[i]) == 1) next; print }
  END { if (bad) exit 1 }' "$SELF/forward-exclude.txt" "$tmp/F0" > "$tmp/F"
[ -s "$tmp/F" ] || { echo "forward-set: the forwarded set of $* is empty" >&2; exit 1; }
cat "$tmp/F"
