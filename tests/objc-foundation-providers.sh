#!/bin/sh
# platform: host-agnostic -- links Foundation-only consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C methods" -- the Foundation providers activate only under their own root,
#       ___recaulk_objc_activate_foundation, which links with Foundation alone, and never replace a method a
#       program already has.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
A="$T/lib/librecaulk-objc.a"
if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  for p in providers own_method; do
    "$CC" $FLAGS -fno-objc-arc -Wall -Werror -c "tests/c/objc_foundation_$p.m" -o "$(tbin "$p.o")"
  done
  "$CC" $FLAGS "$(tbin providers.o)" "$A" -framework Foundation -o "$(tbin unrooted)"
  "$CC" $FLAGS "$(tbin providers.o)" "$A" -Wl,-u,___recaulk_objc_activate_foundation "$T/lib/librecaulk.a" \
    -framework Foundation -o "$(tbin rooted)"
  "$CC" $FLAGS "$(tbin own_method.o)" "$A" -Wl,-u,___recaulk_objc_activate_foundation "$T/lib/librecaulk.a" \
    -framework Foundation -o "$(tbin own-method)"
  for p in rooted own-method; do
    if "$OTOOL" -L "$(tbin "$p")" | grep -Eq '/(AppKit|Carbon)\.framework/'; then bad "$p, a Foundation-only consumer, loads AppKit or Carbon"; fi
    # spec: README.md "Objective-C methods" -- registration finds its class by name, so no NSWorkspace symbol is
    #       imported either way; the provider's own (local, unstripped) symbols show whether it was linked
    syms=$("$NM" "$(tbin "$p")")
    printf '%s\n' "$syms" | grep -q ' ___recaulk_objc_activate_foundation$' || bad "$p has no Foundation root: the symbol check below sees nothing"
    if printf '%s\n' "$syms" | grep -Eq ' ___recaulk_objc_(activate|workspace_open_urls)$'; then bad "$p, a Foundation-only consumer, links the NSWorkspace provider"; fi
  done
  check_loads "$(tbin unrooted)" "$(tbin rooted)" "$(tbin own-method)" || fail=1
  [ "$fail" = 0 ] || exit 1
fi
runtime_half
"$(tbin unrooted)" unrooted || bad "the unrooted program"
"$(tbin rooted)" rooted || bad "the rooted program"
"$(tbin own-method)" || bad "the program with its own languageCode"
[ "$fail" = 0 ] && echo "objc-foundation-providers OK"
exit $fail
