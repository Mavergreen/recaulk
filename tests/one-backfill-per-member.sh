#!/bin/sh
# platform: macOS-only -- links x86_64 Mach-O against librecaulk.a
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. build/sdk-exports.sh

tmp="$(mktemp -d "${TMPDIR:-/tmp}/one-member.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
lib="$T/lib/librecaulk.a"

sdk_exports "$SDK" > "$tmp/sdk"
# platform: MacPorts' private helpers (the private entries of build/forward-exclude.txt) are never defined by a consumer
awk '$3 == "private" && $1 == "prefix" { print "p", $2 } $3 == "private" && $1 == "name" { print "n", $2 }' build/forward-exclude.txt > "$tmp/private"
nm -gU "$lib" | awk 'NF == 3 && $2 ~ /^[A-Za-z]$/ { print $3 }' | LC_ALL=C sort -u \
  | LC_ALL=C comm -23 - "$tmp/sdk" \
  | grep -v '\.eh$' | grep -v '^___recaulk_' \
  | awk 'NR == FNR { if ($1 == "p") pre[++np] = $2; else ex[$2] = 1; next }
         { x = ($0 in ex); for (i = 1; i <= np; i++) if (index($0, pre[i]) == 1) x = 1
           if (!x) print }' "$tmp/private" - > "$tmp/S"

n="$(wc -l < "$tmp/S" | tr -d ' ')"
[ "$n" -gt 100 ] || { echo "FAIL: only $n back-filled names found in $lib"; exit 1; }
for want in _clock_gettime _SecTrustEvaluateWithError; do
  grep -qx "$want" "$tmp/S" || { echo "FAIL: $want is not among the back-filled names"; exit 1; }
done

{
  echo '.section __DATA,__data'
  while read -r s; do printf '.quad "%s"\n' "$s"; done < "$tmp/S"
  printf '.text\n.globl _main\n_main:\n  xorl %%eax, %%eax\n  ret\n'
} > "$tmp/refs.s"
/usr/bin/clang $FLAGS -arch x86_64 -c "$tmp/refs.s" -o "$tmp/refs.o"

fail=0
while read -r s; do
  printf '.globl "%s"\n.section __DATA,__data\n.align 3\n"%s": .quad 0\n' "$s" "$s" > "$tmp/stub.s"
  /usr/bin/clang $FLAGS -arch x86_64 -c "$tmp/stub.s" -o "$tmp/stub.o"
  if ! /usr/bin/clang $FLAGS -arch x86_64 -o "$tmp/a.out" "$tmp/refs.o" "$tmp/stub.o" "$lib" \
      -framework CoreFoundation -framework Security -framework CoreVideo -framework CoreGraphics \
      -framework CoreServices -framework IOKit -lobjc > "$tmp/link.out" 2>&1; then
    # platform: ld names the colliding archive member as lib.a(member.o) under "duplicate symbol"
    member="$(sed -n 's/^.*librecaulk\.a(\(.*\)).*$/\1/p' "$tmp/link.out" | head -1)"
    if grep -q 'duplicate symbol' "$tmp/link.out"; then
      case "$member" in
        mp-*) echo "FAIL: a consumer that defines $s itself collides with MacPorts' member $member, which is not ours to split; offer MacPorts the split upstream, or exempt $s here (spec, one back-fill per member)" ;;
        *) echo "FAIL: a consumer that defines $s itself collides with ${member:-an unnamed member}; split that source so $s stands alone (spec, one back-fill per member)" ;;
      esac
    else
      echo "FAIL: linking a consumer that defines $s failed:"
      cat "$tmp/link.out"
    fi
    fail=1
  fi
done < "$tmp/S"

[ "$fail" -eq 0 ] || exit 1
echo "one-backfill-per-member OK: $n names each link alone"
