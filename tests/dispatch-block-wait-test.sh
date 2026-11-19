#!/bin/sh
# platform: host-agnostic -- builds the staged static archive's x86_64 programs; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Dispatch on 10.9" -- dispatch_block_wait and dispatch_block_notify on a block dispatch_block_create
#       made, and its state seen by a second copy of librecaulk.a in the process (a dylib linking its own).
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
cases='wait-after-async wait-finished wait-timeout notify-after-async notify-finished cancelled-then-run
  release-unrun-with-notify other-copy-cancels other-copy-waits'
if compiling; then
  D="$(dirname "$(tbin x)")"
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -I"$T/include/recaulk" -dynamiclib tests/c/dispatch_block_other.c \
    "$T/lib/librecaulk.a" -install_name @executable_path/libother.dylib -o "$D/libother.dylib"
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -I"$T/include/recaulk" tests/c/dispatch_block_wait.c "$T/lib/librecaulk.a" \
    "$D/libother.dylib" -o "$(tbin blocks)"
  check_loads "$(tbin blocks)" "$D/libother.dylib"
fi
runtime_half
fail=0
for c in $cases; do
  if out="$("$(tbin blocks)" "$c" 2>&1)"; then echo "ok $c"; else echo "FAIL $c: $out"; fail=1; fi
done
[ "$fail" = 0 ] && echo "dispatch-block-wait OK"
exit "$fail"
