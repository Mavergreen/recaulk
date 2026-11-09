#!/bin/sh
# platform: host-agnostic -- builds x86_64 programs against librecaulk.a and libRecaulkSystem.dylib; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Closing a socket" -- closing or dup2ing over a socket another thread is entering a read,
#       accept or recv on never hangs, from a program that links librecaulk.a and one linked against
#       libRecaulkSystem.dylib. Without Recaulk's close and dup2, 10.9 hangs within a few hundred.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
cc() { "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror "$@"; }
if compiling; then
  cc tests/c/socket_close_race.c "$T/lib/librecaulk.a" -o "$(tbin static)"
  cc tests/c/socket_close_race.c -L"$T/lib" -lRecaulkSystem -o "$(tbin dylib)"
  check_loads "$(tbin static)" "$(tbin dylib)"
  for s in _close '_close$NOCANCEL' _dup2; do
    "$NM" -u "$(tbin static)" | grep -qxF "$s" \
      && { echo "FAIL: the librecaulk.a program imports $s from libSystem instead of carrying Recaulk's"; exit 1; }
  done
  for s in _close _dup2; do
    "$NM" -m "$(tbin dylib)" | grep -qF "(undefined) external $s (from libRecaulkSystem)" \
      || { echo "FAIL: the libRecaulkSystem.dylib program does not take $s from the dylib"; exit 1; }
  done
fi
runtime_half
fail=0
for p in static dylib; do
  for m in tcp accept udp; do
    for how in dup2 close; do
      # platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it is set where the program is exec'd
      out=$(DYLD_LIBRARY_PATH="$T/lib" "$(tbin $p)" $m $how 3000 2>&1) && echo "$p $out" || { echo "$p $m $how: $out"; fail=1; }
    done
  done
done
[ "$fail" = 0 ] && echo "socket-close-race OK"
exit $fail
