#!/bin/sh
# platform: host-agnostic -- builds the staged static archive and dylib's x86_64 programs; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Dispatch on 10.9" -- through Recaulk's declarations, a program linking librecaulk.a and one relinked
#       onto libRecaulkSystem.dylib: global queues by QoS class, the queue QoS query, the autorelease-frequency
#       attribute, the targeted queue, and the not and barrier assertions (on the queue returns or traps as named).
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror -I"$T/include/recaulk" tests/c/dispatch_modern.c "$T/lib/librecaulk.a" -o "$(tbin static)"
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror -I"$T/include/recaulk" tests/c/dispatch_modern.c -L"$T/lib" -lRecaulkSystem -o "$(tbin dylib)"
  check_loads "$(tbin static)" "$(tbin dylib)"
fi
runtime_half
returns='global-qos queue-qos-class autorelease-frequency create-with-target assert-in-sync not-off-on-pthread
  not-other-queue-block barrier-in-sync'
traps_not='not-in-sync not-target-in-block not-main-on-main-thread not-null'
traps_on='barrier-off-on-pthread'
err="$(mktemp "${TMPDIR:-/tmp}/dispatch-modern.XXXXXX")"
trap 'rm -f "$err"' EXIT
fail=0
for v in static dylib; do
  for c in $returns $traps_not $traps_on; do
    # platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it is set where the program is exec'd
    rc=0; DYLD_LIBRARY_PATH="$T/lib" "$(tbin "$v")" "$c" > "$err" 2>&1 || rc=$?
    case " $(echo $traps_not) " in *" $c "*) want='Block was not expected to execute on queue' ;; *)
    case " $(echo $traps_on) " in *" $c "*) want='Block was expected to execute on queue' ;; *) want= ;; esac ;; esac
    if [ -n "$want" ]; then
      if [ "$rc" -le 128 ] || ! grep -q "BUG IN CLIENT OF LIBDISPATCH: Assertion failed: $want" "$err"; then
        echo "FAIL $v $c: want a trap ($want); exited $rc: $(cat "$err")"; fail=1
      else echo "ok $v $c traps"; fi
    elif [ "$rc" != 0 ]; then echo "FAIL $v $c: exited $rc: $(cat "$err")"; fail=1
    else echo "ok $v $c"; fi
  done
done
[ "$fail" = 0 ] && echo "dispatch-modern OK"
exit "$fail"
