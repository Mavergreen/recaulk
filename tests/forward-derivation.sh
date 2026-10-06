#!/bin/sh
# platform: macOS-only -- nm reads Mach-O archives
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. build/sdk-exports.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/fwd-derive.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

mp="$W/macports-legacy-support-$(macports_version)/lib/libMacportsLegacySupport.a"
[ -f "$mp" ] || { echo "FAIL: no MacPorts archive at $mp: run sh build/build-lib.sh"; exit 1; }
bf="$W/librecaulk-backfills.a"
lib="$T/lib/librecaulk.a"

sdk_exports "$SDK" > "$tmp/sdk"
nm -gU "$mp" "$bf" > "$tmp/src.nm"
nm -m "$mp" "$bf" | awk '/private external/ { print $NF }' | LC_ALL=C sort -u > "$tmp/src.pext"
awk 'NF == 3 && $2 == "T" { print $3 }' "$tmp/src.nm" | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$tmp/src.pext" > "$tmp/src.T"
policy=build/forward-exclude.txt
derive() {
  LC_ALL=C comm -23 "$tmp/src.T" "$1/sdk" | grep -v '\.eh$' | grep -v '^___recaulk_' > "$1/F0" || true
  awk -v OUT="$1/E" -v DATA="$1/Edata" '
    NR == FNR { if ($1 == "prefix") { pre[++np] = $2; prewhy[np] = $3 } else if ($1 == "name") ex[$2] = $3; next }
    { why = ($0 in ex) ? ex[$0] : ""
      for (i = 1; i <= np && why == ""; i++) if (index($0, pre[i]) == 1) why = prewhy[i]
      if (why == "") print; else { print > OUT; if (why == "data") print > DATA } }' "$policy" "$1/F0" > "$1/F"
  touch "$1/E" "$1/Edata"
}
derive "$tmp"
[ -s "$tmp/F" ] || { echo "FAIL: the forwarded set computed from $mp and $bf is empty"; exit 1; }
# platform: a modern host reads the SDK from the .tbd files tapi made of its stubs (fetch_sdk.sh), and there __error is an SDK export: 10.9's libobjc.A.dylib exports it in its export trie, not its symbol table, which is all 10.9's nm reads
mkdir "$tmp/modern"
printf '%s\n' __error | LC_ALL=C sort -u - "$tmp/sdk" > "$tmp/modern/sdk"
derive "$tmp/modern"
cmp -s "$tmp/F" "$tmp/modern/F" \
  || bad "the forwarded set differs between 10.9's view of the SDK and a modern host's, where libobjc.A.dylib also exports __error: $(diff "$tmp/F" "$tmp/modern/F" | grep '^[<>]' | tr '\n' ' ')"

# platform: nm -A prefixes each line with archive:member:, and an undefined symbol has no address column
nm -A "$lib" | awk '
  { member = $1; sub(/^.*\.a:/, "", member); sub(/:$/, "", member)
    if (NF == 4) print member, $3, $4
    else if (NF == 3) print member, $2, $3 }' > "$tmp/lib.syms"

awk '$1 ~ /^fwd-/ && $2 == "T" && $3 !~ /^___recaulk_/ && $3 !~ /\.eh$/ { print $3 }' "$tmp/lib.syms" \
  | LC_ALL=C sort -u > "$tmp/fwd"
if ! diff "$tmp/F" "$tmp/fwd" > "$tmp/diff"; then
  bad "the trampolines (fwd- members of librecaulk.a) must cover exactly the forwarded set (spec, Back-fills defer to the system); < forwarded but no trampoline, > a trampoline outside the set:"
  sed 's/^/  /' "$tmp/diff" | grep '^  [<>]'
fi

awk '$1 !~ /^fwd-/' "$tmp/lib.syms" > "$tmp/nonfwd"
awk '$2 == "T" && $3 ~ /^___recaulk_impl_/ && $3 !~ /\.eh$/ { print $3, $1 }' "$tmp/lib.syms" | LC_ALL=C sort > "$tmp/impls"
awk '$2 != "U" { print $3, $1 }' "$tmp/nonfwd" | LC_ALL=C sort -u > "$tmp/nonfwd.defs"
while read -r n; do
  impl="___recaulk_impl_${n#_}"
  c="$(awk -v s="$impl" '$1 == s' "$tmp/impls" | wc -l | tr -d ' ')"
  [ "$c" = 1 ] || bad "$impl is defined by $c members of librecaulk.a, want exactly 1: $n's implementation must be renamed behind its trampoline"
  definers="$(awk -v s="$n" '$1 == s { print $2 }' "$tmp/nonfwd.defs" | tr '\n' ' ')"
  [ -z "$definers" ] || bad "$n is still defined by non-fwd members: ${definers}-- the definition must be renamed $impl"
done < "$tmp/F"

renamed_refs="$(awk '$2 == "U" && $3 ~ /^___recaulk_impl_/ { print $1 ": " $3 }' "$tmp/nonfwd" | tr '\n' ' ')"
[ -z "$renamed_refs" ] \
  || bad "a reference from one object to a forwarded function another defines must stay _<n>, so it reaches the trampoline and every caller in the process runs the same implementation; renamed: $renamed_refs"

lock="$(awk '$2 == "T" && $3 == "___recaulk_impl_os_unfair_lock_lock_with_options" { print $1 }' "$tmp/lib.syms")"
if [ -z "$lock" ]; then
  bad "no member defines ___recaulk_impl_os_unfair_lock_lock_with_options"
elif ! awk -v m="$lock" '$1 == m && $2 == "U" && $3 == "_os_unfair_lock_lock"' "$tmp/lib.syms" | grep -q .; then
  bad "$lock does not call _os_unfair_lock_lock through its trampoline: on 10.12-10.14 the system has os_unfair_lock_lock and os_unfair_lock_unlock but not _with_options, and a lock taken by MacPorts' implementation and released by the system's aborts"
fi

swift="$(awk '$2 == "T" && $3 == "___recaulk_impl__objc_realizeClassFromSwift" { print $1 }' "$tmp/lib.syms")"
if [ -z "$swift" ]; then
  bad "no member defines ___recaulk_impl__objc_realizeClassFromSwift"
elif ! awk -v m="$swift" '$1 == m && $2 == "U" && $3 == "_objc_readClassPair"' "$tmp/lib.syms" | grep -q .; then
  bad "$swift does not call _objc_readClassPair through its trampoline: on 10.10-10.14.3 the system has objc_readClassPair but not _objc_realizeClassFromSwift, and ours, written for 10.9's class layout, must not realize classes there"
fi
for n in ____chkstk_darwin __error _macports_legacy_sysconf ___mpls_best_fchdir; do
  for v in "$tmp" "$tmp/modern"; do
    view="this host's"; [ "$v" = "$tmp" ] || view="a modern host's"
    grep -qx -- "$n" "$v/E" || grep -qx -- "$n" "$v/sdk" \
      || bad "$n is neither excluded by $policy nor an SDK export in $view view of the SDK:____chkstk_darwin keeps every register but rax (no trampoline may stand in front of it), and __error, _macports_legacy_ and ___mpls_ names are MacPorts-private, never system API"
  done
done
for pair in _DNSServiceGetAddrInfoEx:_kDNSServiceAttrAllowFailover __os_log_impl:__os_log_default \
    __os_log_error_impl:__os_log_default _os_log_type_enabled:__os_log_default \
    __os_signpost_emit_with_name_impl:__os_log_default _os_signpost_enabled:__os_log_default; do
  n="${pair%%:*}"; data="${pair#*:}"
  grep -qx -- "$n" "$tmp/Edata" || bad "$n is not excluded as data by $policy: it consumes a data symbol of ours ($data), and data is never forwarded, so the system's $n would be handed our $data"
done
while read -r n; do
  ! grep -qx -- "$n" "$tmp/fwd" || bad "$n is excluded by $policy, but a fwd- member defines it"
  awk -v s="$n" '$1 !~ /^fwd-/ && $2 == "T" && $3 == s' "$tmp/lib.syms" | grep -q . \
    || bad "$n is excluded by $policy, so it must stay defined unrenamed, but no member of librecaulk.a defines it"
  ! awk -v s="___recaulk_impl_${n#_}" '$3 == s' "$tmp/lib.syms" | grep -q . \
    || bad "$n is excluded by $policy, but librecaulk.a names ___recaulk_impl_${n#_}"
done < "$tmp/E"

# platform: nm prints addresses in hex and otool -rv names an extern relocation's symbol last; BSD awk has no strtonum
same_object_refs() {
  {
    otool -l "$1" | awk '$1 == "sectname" { s = $2 } $1 == "segname" && s != "" { g = $2 } $1 == "addr" && s != "" { print "S", g "," s, $2; s = "" }'
    nm "$1" | awk 'NF == 3 && ($2 == "T" || $2 == "t") && $3 !~ /\.eh$/ { print "Y", $1, $3 }'
    otool -rv "$1" | awk '
      /^Relocation information/ { sec = $3; sub(/^\(/, "", sec); sub(/\)$/, "", sec); next }
      $1 ~ /^[0-9a-f]+$/ && $4 == "True" { print "R", sec, $1, $NF }'
  } | awk -v M="$(basename "$1")" '
    function num(v,  i, r) {
      sub(/^0x/, "", v); v = tolower(v); r = 0
      for (i = 1; i <= length(v); i++) r = r * 16 + index("0123456789abcdef", substr(v, i, 1)) - 1
      return r
    }
    $1 == "S" { base[$2] = num($3) }
    $1 == "Y" { ns++; ya[ns] = num($2); yn[ns] = $3 }
    $1 == "R" && $4 ~ /^___recaulk_impl_/ && $4 !~ /\.eh$/ {
      if ($2 == "__TEXT,__text") {
        a = base[$2] + num($3); best = -1; caller = "?"
        for (i = 1; i <= ns; i++) if (ya[i] <= a && ya[i] > best) { best = ya[i]; caller = yn[i] }
      } else caller = "(" $2 ")"
      if (caller != $4) {
        c = caller; sub(/^___recaulk_impl_/, "_", c); d = $4; sub(/^___recaulk_impl_/, "_", d)
        print M, c, "->", d
      }
    }'
}
mkdir "$tmp/members"
(cd "$tmp/members" && ar -x "$lib")
for m in "$tmp"/members/*.o; do
  case "$(basename "$m")" in fwd-*) continue ;; esac
  same_object_refs "$m"
done | LC_ALL=C sort -u > "$tmp/same"
echo "same-object references, renamed with their caller (they bypass the trampoline):"
sed 's/^/  /' "$tmp/same"
expected=tests/fixtures/forward-same-object.txt
diff "$expected" "$tmp/same" > "$tmp/same.diff" || true
if grep -q '^>' "$tmp/same.diff"; then
  bad "new same-object references against $expected: judge each in PROVENANCE.md (a caller newer than its callee runs our callee where the system has its own), then add it to the fixture"
  sed -n 's/^> /  /p' "$tmp/same.diff"
fi
if grep -q '^<' "$tmp/same.diff"; then
  echo "note: these same-object references are gone; remove them from $expected and from PROVENANCE.md's table:"
  sed -n 's/^< /  /p' "$tmp/same.diff"
fi

grep -qx _clock_gettime "$tmp/F" || bad "_clock_gettime (MacPorts) is not in the forwarded set"
grep -qx _CCRandomGenerateBytes "$tmp/F" || bad "_CCRandomGenerateBytes (ours) is not in the forwarded set"
for n in _sysconf _pthread_get_stacksize_np; do
  ! grep -qx "$n" "$tmp/F" || bad "$n is in the forwarded set, but 10.9 exports it: MacPorts' fixes to 10.9-exported functions are never forwarded"
  ! grep -qx "$n" "$tmp/fwd" || bad "a fwd- member defines $n, but 10.9 exports it"
done
awk '$1 ~ /^mp-/ && $2 == "T" && $3 == "_sysconf"' "$tmp/lib.syms" | grep -q . \
  || bad "no mp- member of librecaulk.a defines _sysconf unrenamed: MacPorts' fix to a 10.9-exported function must stay as it is"
awk 'NF == 3 && $2 != "T" && $2 != "U" { print $3 }' "$tmp/src.nm" | LC_ALL=C sort -u > "$tmp/data"
inF="$(LC_ALL=C comm -12 "$tmp/data" "$tmp/F" | tr '\n' ' ')"
[ -z "$inF" ] || bad "data symbols are never forwarded, but these are in the set: $inF"

[ "$fail" = 0 ] && echo "forward-derivation OK ($(wc -l < "$tmp/F" | tr -d ' ') forwarded)"
exit $fail
