#!/bin/sh
# platform: macOS-only -- nm and otool read Mach-O archives and objects
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. build/sdk-exports.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/rule1.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

sdk_exports "$SDK" > "$tmp/sdk"
for want in _kevent64 _CFRetain _objc_msgSend _SecTrustEvaluate _LSCopyDefaultHandlerForURLScheme; do
  grep -qx "$want" "$tmp/sdk" || bad "could not read the 10.9 SDK's exports; nm cannot read the file that defines $want?"
done
[ "$(wc -l < "$tmp/sdk" | tr -d ' ')" -gt 10000 ] \
  || bad "could not read the 10.9 SDK's exports; nm cannot read some of its libraries? only $(wc -l < "$tmp/sdk" | tr -d ' ') names"
[ "$fail" = 0 ] || exit 1

# platform: Apple clang 6 on 10.9 emits a <sym>.eh beside each function; it is not an API symbol
# platform: nm -m names a hidden definition "private external", in 10.9's nm and in llvm-nm alike
defined_in_archive() {
  "${NM:-nm}" -gU -m -A "$1" | awk '
    $NF !~ /\.eh$/ {
      member = $1; sub(/^.*\.a:/, "", member); sub(/:$/, "", member)
      print member, $NF, (/ private external / ? "hidden" : "visible")
    }'
}

# Rule 1's one exception, exact and declared: build/image-local-shadows.txt lists each hidden
# definition allowed to shadow a 10.9 export inside the linking image, with its reason.
grep -v '^#' build/image-local-shadows.txt | awk 'NF { print $1, $2 }' > "$tmp/shadows"
defined_in_archive "$W/librecaulk-backfills.a" > "$tmp/defined"
while read -r member sym vis; do
  grep -qxF -- "$sym" "$tmp/sdk" || continue
  if [ "$vis" = hidden ] && grep -qxF -- "$member $sym" "$tmp/shadows"; then continue; fi
  if [ "$vis" = hidden ]; then
    echo "$member defines $sym hidden, which 10.9 already exports, and build/image-local-shadows.txt does not list it: list it with its reason, or move its source to src/overrides/ (spec rule 1)"
  else
    echo "$member defines $sym, which 10.9 already exports: it is an override; move its source to src/overrides/ (spec rule 1)"
  fi
done < "$tmp/defined" > "$tmp/bad1"
while read -r member sym; do
  grep -qxF -- "$member $sym hidden" "$tmp/defined" \
    || echo "build/image-local-shadows.txt lists $sym in $member, which no hidden definition there matches: delete the entry, or make it hidden again"
done < "$tmp/shadows" >> "$tmp/bad1"
if [ -s "$tmp/bad1" ]; then
  cat "$tmp/bad1" | sed 's/^/FAIL: /'
  fail=1
fi

for o in "$W"/overrides/*.o; do
  "${NM:-nm}" -gU "$o" | awk 'NF == 3 && $2 ~ /^[A-Za-z]$/ && $3 !~ /\.eh$/ { print $3 }' > "$tmp/names"
  [ -s "$tmp/names" ] || continue
  if ! grep -qxF -f "$tmp/names" "$tmp/sdk"; then
    bad "$(basename "$o") replaces nothing 10.9 has: it is a back-fill; move it to src/backfills/"
  fi
done

mkdir "$tmp/members"
(cd "$tmp/members" && ar -x "$W/librecaulk-backfills.a")
for m in "$tmp"/members/*.o; do
  if otool -l "$m" | grep -q 'sectname __mod_init_func'; then
    bad "$(basename "$m") has a constructor: a constructor in librecaulk.a runs in every product that force-loads it; that is an override's job"
  fi
done
mkdir "$tmp/all"
(cd "$tmp/all" && ar -x "$T/lib/librecaulk.a")
for m in "$tmp"/all/fwd-*.o; do
  [ -f "$m" ] || continue
  if otool -l "$m" | grep -q 'sectname __mod_init_func'; then
    bad "$(basename "$m") has a constructor: a constructor in librecaulk.a runs in every product that force-loads it; that is an override's job"
  fi
done

[ "$fail" = 0 ] && echo "rule 1 OK"
exit $fail
