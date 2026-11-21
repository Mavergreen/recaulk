#!/bin/sh
# platform: host-agnostic -- reads MacPorts' archive and librecaulk.a with llvm-nm
# spec: build/macports-superseded.txt -- each MacPorts member Recaulk leaves out is one MacPorts' archive has, each
#       carries a reason, and librecaulk.a still defines, in a member of Recaulk's own, every global it defined
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. build/lib.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
mp="$(ls -d "$B"/macports-legacy-support-*/lib/libMacportsLegacySupport.a 2>/dev/null | head -1)"
[ -f "$mp" ] || mp="$(find "$B" -name libMacportsLegacySupport.a 2>/dev/null | head -1)"
[ -f "$mp" ] || { echo "FAIL: no built libMacportsLegacySupport.a under $B to compare with"; exit 1; }
grep -v '^#' build/macports-superseded.txt | awk 'NF' > "$B/superseded.list"
[ -s "$B/superseded.list" ] || { echo "macports-superseded OK (none)"; exit 0; }
while read -r m reason; do
  [ -n "$reason" ] || bad "build/macports-superseded.txt gives $m no reason"
  syms="$("$NM" -gU -m "$mp" 2>/dev/null | awk -v m="$m" '/^$/ { next } /:$/ { cur = $0; sub(/:$/, "", cur); sub(/^.*\(/, "", cur); sub(/\)$/, "", cur); next } cur == m && / external / && !/private external/ { print $NF }')"
  [ -n "$syms" ] || { bad "MacPorts' archive has no member $m with globals"; continue; }
  for s in $syms; do
    "$NM" -gU -m -A "$T/lib/librecaulk.a" | grep -q "recaulk-[^:]*: .* external $s\$" || bad "librecaulk.a no longer defines $s, which MacPorts' $m did"
  done
  "$NM" -A "$T/lib/librecaulk.a" | grep -q "mp-$m:" && bad "librecaulk.a still carries MacPorts' mp-$m"
done < "$B/superseded.list"
[ "$fail" = 0 ] && echo "macports-superseded OK"
exit $fail
