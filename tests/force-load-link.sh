#!/bin/sh
# platform: host-agnostic -- links x86_64 programs against librecaulk.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "How to use" -- each member of librecaulk.a carries the frameworks and libraries it needs
#       (LC_LINKER_OPTION), so a program that force-loads the whole archive links with no flags of its own,
#       and one that links it normally gains nothing it does not use.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
if compiling; then
  D="$(dirname "$(tbin x)")"
  printf 'int main(void) { return 0; }\n' > "$D/empty.c"
  # platform: --no-default-config keeps clang22's own librecaulk.a and frameworks off the link, so only the
  #   archive's members can supply what they need
  "$CC" --no-default-config $FLAGS -arch x86_64 "$D/empty.c" -Wl,-force_load,"$T/lib/librecaulk.a" \
    -o "$(tbin force-loaded)" > "$D/force.log" 2>&1 \
    || { bad "a program force-loading librecaulk.a with no flags of its own does not link:"; grep 'undefined symbol' "$D/force.log" | head -8 | sed 's/^/    /'; }
  "$CC" --no-default-config $FLAGS -arch x86_64 "$D/empty.c" "$T/lib/librecaulk.a" -o "$(tbin normal)"
  extra="$("$OTOOL" -L "$(tbin normal)" | sed -n '2,$p' | grep -v '/usr/lib/libSystem\.B\.dylib' || true)"
  [ -z "$extra" ] || bad "a program linking librecaulk.a normally, using none of it, loads more than libSystem:$(printf '\n%s' "$extra")"
  [ "$fail" = 0 ] || exit 1
  check_loads "$(tbin force-loaded)" "$(tbin normal)"
fi
runtime_half
"$(tbin force-loaded)" || bad "the force-loaded program does not run"
"$(tbin normal)" || bad "the normally linked program does not run"
[ "$fail" = 0 ] && echo "force-load-link OK"
exit $fail
