#!/bin/sh
# platform: host-agnostic -- builds the staged static archive and dylib's x86_64 programs; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Queue assertions" -- each case through a program that links librecaulk.a and one relinked onto
#       libRecaulkSystem.dylib: on the queue it returns, provably off it traps, and where 10.9 cannot tell it returns.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
sym='_dispatch_assert_queue$V2'
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror tests/c/dispatch_assert_queue.c "$T/lib/librecaulk.a" -o "$(tbin static)"
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror tests/c/dispatch_assert_queue.c -L"$T/lib" -lRecaulkSystem -o "$(tbin dylib)"
  check_loads "$(tbin static)" "$(tbin dylib)"
  "$NM" -u "$(tbin static)" | grep -qxF "$sym" \
    && { echo "FAIL: the librecaulk.a program imports $sym instead of carrying Recaulk's"; exit 1; }
  "$NM" -m "$(tbin dylib)" | grep -qF "(undefined) external $sym (from libRecaulkSystem)" \
    || { echo "FAIL: the libRecaulkSystem.dylib program does not take $sym from the dylib"; exit 1; }
fi
runtime_half
returns='main-on-main-thread main-in-main-block main-in-sync-from-main-thread serial-in-sync serial-in-async
  target-in-block global-in-block outer-in-nested-sync main-outer-in-nested-sync-after-dispatch-main other-queue-block
  serial-on-main-thread global-on-main-thread serial-in-main-block'
traps='serial-off-on-pthread main-off-on-pthread global-off-on-pthread main-off-in-worker target-off-after-block null'
err="$(mktemp "${TMPDIR:-/tmp}/dispatch-assert-queue.XXXXXX")"
trap 'rm -f "$err"' EXIT
fail=0
for v in static dylib; do
  for c in $returns $traps; do
    # platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it is set where the program is exec'd
    rc=0; DYLD_LIBRARY_PATH="$T/lib" "$(tbin "$v")" "$c" 2>"$err" || rc=$?
    case " $traps " in
      *" $c "*)
        if [ "$rc" -le 128 ] || ! grep -q 'BUG IN CLIENT OF LIBDISPATCH: Assertion failed: Block was expected to execute on queue' "$err"; then
          echo "FAIL $v $c: off the queue, want a trap with libdispatch's message; exited $rc: $(cat "$err")"; fail=1
        else echo "ok $v $c traps"; fi ;;
      *)
        if [ "$rc" != 0 ]; then echo "FAIL $v $c: on the queue (or not provably off it), want a return; exited $rc: $(cat "$err")"; fail=1
        else echo "ok $v $c returns"; fi ;;
    esac
  done
done
[ "$fail" = 0 ] && echo "dispatch-assert-queue OK"
exit "$fail"
