#!/bin/sh
# platform: host-agnostic -- compiles x86_64 Mach-O objects and reads them with nm
# spec: README.md "How to use" -- a hidden name or a MacPorts-private name becomes ___recaulk_<name> in every
#       member that defines or references it, so members that share it still link together
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
DRYDOCK="$B/drydock/drydock-macho-rewrite"
[ -x "$DRYDOCK" ] || { echo "FAIL: $DRYDOCK is not executable: sh build/build-lib.sh fetches it"; exit 1; }
D="$(mktemp -d "${TMPDIR:-/tmp}/rename-private.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

printf '%s\n' '__attribute__((visibility("hidden"), noinline)) int helper(int x) { return x * 3; }' \
  'int __mpls_shared(int x) { return x + 2; }' 'int api_def(int x) { return helper(x) + __mpls_shared(x); }' > "$D/def.c"
printf '%s\n' 'int helper(int);' 'int __mpls_shared(int);' 'int api_ref(int x) { return helper(x) - __mpls_shared(x); }' > "$D/ref.c"
printf '%s\n' 'int api_def(int); int api_ref(int);' 'int main(void) { return api_def(1) + api_ref(1); }' > "$D/main.c"
for n in def ref main; do
  "$CC" $FLAGS -arch x86_64 -Os -c "$D/$n.c" -o "$D/$n.o"
done
sh build/rename-private.sh "$DRYDOCK" "$D/def.o" "$D/ref.o" || bad "rename-private failed on well-formed objects"
syms() { "$NM" "$1" | awk '{ print $2, $NF }' | tr '\n' ' '; }
has() { "$NM" "$1" | awk -v t="$2" -v n="$3" '$(NF-1) == t && $NF == n' | grep -q .; }
for pair in _helper:___recaulk_helper ___mpls_shared:___recaulk_mpls_shared; do
  old="${pair%%:*}"; new="${pair#*:}"
  has "$D/def.o" T "$new" || bad "def.o does not define $new: $(syms "$D/def.o")"
  has "$D/ref.o" U "$new" || bad "ref.o, which only references $old, does not reference it as $new, so linking both members would leave $new or $old undefined: $(syms "$D/ref.o")"
  for o in def ref; do
    ! "$NM" "$D/$o.o" | awk '{ print $NF }' | grep -qx -- "$old" || bad "$o.o still names $old: $(syms "$D/$o.o")"
  done
done
for n in _api_def _api_ref; do
  "$NM" "$D/def.o" "$D/ref.o" | awk '$2 == "T" { print $3 }' | grep -qx -- "$n" || bad "$n, an API name, was renamed or lost"
done
"$CC" $FLAGS -arch x86_64 "$D/main.o" "$D/def.o" "$D/ref.o" -o "$D/a.out" > "$D/link.out" 2>&1 \
  || bad "a program linking both renamed members does not link: $(cat "$D/link.out")"

[ "$fail" = 0 ] && echo "rename-private OK"
exit "$fail"
