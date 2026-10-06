#!/bin/sh
# platform: macOS-only -- compiles x86_64 Mach-O objects and reads them with nm and otool
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
DRYDOCK="$B/drydock/drydock-macho-rewrite"
[ -x "$DRYDOCK" ] || { echo "FAIL: $DRYDOCK is not executable: sh build/build-lib.sh fetches it"; exit 1; }
D="$(mktemp -d "${TMPDIR:-/tmp}/rename-impls.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

printf '%s\n' '__attribute__((noinline)) int g(int x) { return x * 3; }' 'int f(int x) { return g(x) + 1; }' > "$D/def.c"
printf '%s\n' 'int g(int);' 'int h(int x) { return g(x) - 1; }' > "$D/ref.c"
for n in def ref; do
  /usr/bin/clang $FLAGS -arch x86_64 -Os -c "$D/$n.c" -o "$D/$n.o"
done
printf '%s\n' _f _g > "$D/symbols"
cp "$D/def.o" "$D/pad.o"
printf '\n\n\n\n' >> "$D/pad.o"
mkdir "$D/members"
/usr/bin/ar -r "$D/pad.a" "$D/pad.o" 2>/dev/null
(cd "$D/members" && /usr/bin/ar -x "$D/pad.a")

# platform: clang 6 (10.9) gives each function an _<n>.eh symbol; Xcode 26's clang emits compact unwind and none, as -fno-asynchronous-unwind-tables does here
/usr/bin/clang $FLAGS -arch x86_64 -Os -fno-asynchronous-unwind-tables -c "$D/def.c" -o "$D/noeh.o"

sh build/rename-impls.sh "$DRYDOCK" "$D/symbols" "$D/def.o" "$D/ref.o" "$D/pad.o" "$D/noeh.o" || bad "rename-impls failed on well-formed objects"
syms() { nm "$1" | awk '{ print $NF }' | tr '\n' ' '; }
names() { nm "$1" | awk '{ print $NF }' | grep -qx -- "$2"; }
for o in def noeh; do
  { names "$D/$o.o" ___recaulk_impl_f && names "$D/$o.o" ___recaulk_impl_g; } \
    || bad "$o.o does not define ___recaulk_impl_f and ___recaulk_impl_g: $(syms "$D/$o.o")"
  ! { names "$D/$o.o" _f || names "$D/$o.o" _g; } || bad "$o.o still names _f or _g: $(syms "$D/$o.o")"
  otool -rv "$D/$o.o" | grep -q 'BRANCH.*___recaulk_impl_g$' || bad "$o.o: f's call to g in the same object does not name ___recaulk_impl_g"
done
nm "$D/ref.o" | grep -q ' U _g$' \
  || bad "ref.o only references _g, which another object defines; the reference must stay _g so it reaches the trampoline: $(syms "$D/ref.o")"

cp "$D/members/pad.o" "$D/padded.o"
sh build/rename-impls.sh "$DRYDOCK" "$D/symbols" "$D/padded.o" || bad "rename-impls failed on an ar -x member with archive padding"
[ "$(syms "$D/padded.o")" = "$(syms "$D/def.o")" ] || bad "a padded member was renamed differently from an unpadded object: $(syms "$D/padded.o")"

printf '%s\n' 'int k(int x) { return x; }' > "$D/none.c"
/usr/bin/clang $FLAGS -arch x86_64 -Os -c "$D/none.c" -o "$D/none.o"
cp "$D/none.o" "$D/none.before"
sh build/rename-impls.sh "$DRYDOCK" "$D/symbols" "$D/none.o" || bad "rename-impls failed on an object defining none of the symbols"
cmp -s "$D/none.o" "$D/none.before" || bad "an object defining none of the symbols was changed"

printf '%s\n' '#!/bin/sh' 'echo refused >&2' 'exit 1' > "$D/refuser"
/usr/bin/clang $FLAGS -arch x86_64 -Os -c "$D/def.c" -o "$D/refused.o"
rc=0; err="$(sh build/rename-impls.sh "$D/refuser" "$D/symbols" "$D/refused.o" 2>&1)" || rc=$?
[ "$rc" = 1 ] || bad "a drydock failure exited $rc, want 1"
case "$err" in *"drydock refused $D/refused.o"*) ;; *) bad "a drydock failure does not name the object: $err" ;; esac

[ "$fail" = 0 ] && echo "rename-impls OK"
exit $fail
