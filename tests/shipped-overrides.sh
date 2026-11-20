#!/bin/sh
# platform: host-agnostic -- nm reads the staged archive and the 10.9 SDK's libraries
# spec: README.md "Fixes to functions 10.9 has" -- share/recaulk/system-overrides.txt names, as
#       `<member> <symbol>`, every global librecaulk.a defines that 10.9 already exports, hidden or not, so a
#       product's conformance check can fail a binary that imports one from the system (a link-order miss).
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. build/sdk-exports.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
d="$(mktemp -d "${TMPDIR:-/tmp}/overrides.XXXXXX")"
trap 'rm -rf "$d"' EXIT
list="$T/share/recaulk/system-overrides.txt"
[ -f "$list" ] || { echo "FAIL: $list is not staged"; exit 1; }
sdk_exports "$SDK" > "$d/sdk"
"$NM" -gU -m -A "$T/lib/librecaulk.a" | awk '$NF !~ /\.eh$/ { m = $1; sub(/^.*\.a:/, "", m); sub(/:$/, "", m); print m, $NF }' \
  | while read -r m s; do grep -qxF -- "$s" "$d/sdk" && echo "$m $s"; done | LC_ALL=C sort -u > "$d/want"
grep -v '^#' "$list" | awk 'NF' | LC_ALL=C sort -u > "$d/have"
cmp -s "$d/want" "$d/have" || bad "the list is not exactly librecaulk.a's definitions of 10.9 exports: $(diff "$d/have" "$d/want" | grep '^[<>]' | head -5 | tr '\n' ' ')"
# spec: the hidden fixes build/image-local-shadows.txt lists, and MacPorts' public pthread_get_stacksize_np, are among them
grep -v '^#' build/image-local-shadows.txt | awk 'NF { print $1, $2 }' | while read -r m s; do
  grep -qxF -- "$m $s" "$d/have" || echo "FAIL: the list lacks $m $s, which build/image-local-shadows.txt lists"
done | grep . && fail=1
grep -qxF 'mp-pthread_get_stacksize_np.o _pthread_get_stacksize_np' "$d/have" || bad "the list lacks MacPorts' pthread_get_stacksize_np"
exit $fail
