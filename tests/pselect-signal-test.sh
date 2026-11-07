#!/bin/sh
# platform: macOS-only -- builds the staged static archive and dylib's x86_64 programs; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Waiting with pselect" -- every case through all five of 10.9's pselect symbols, from a
#       program that links librecaulk.a and one relinked onto libRecaulkSystem.dylib.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
cc() { /usr/bin/clang $FLAGS -arch x86_64 -Wall -Wextra -Werror "$@"; }
if compiling; then
  cc tests/c/pselect_signal.c "$T/lib/librecaulk.a" -o "$(tbin static)"
  cc tests/c/pselect_signal.c -L"$T/lib" -lRecaulkSystem -o "$(tbin dylib)"
  check_loads "$(tbin static)" "$(tbin dylib)"
  for s in _pselect '_pselect$1050' '_pselect$DARWIN_EXTSN' '_pselect$DARWIN_EXTSN$NOCANCEL' '_pselect$NOCANCEL'; do
    nm -u "$(tbin static)" | grep -qxF "$s" \
      && { echo "FAIL: the librecaulk.a program imports $s from libSystem instead of carrying Recaulk's"; exit 1; }
    nm -m "$(tbin dylib)" | grep -qF "(undefined) external $s (from libRecaulkSystem)" \
      || { echo "FAIL: the libRecaulkSystem.dylib program does not take $s from the dylib"; exit 1; }
  done
fi
runtime_half
fail=0
out="$("$(tbin static)" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out" | grep -v '^ok ' || :
[ "$rc" = 0 ] || { echo "FAIL: the librecaulk.a program exited $rc"; fail=1; }
# platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it is set where the program is exec'd
out="$(DYLD_LIBRARY_PATH="$T/lib" "$(tbin dylib)" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out" | grep -v '^ok ' || :
[ "$rc" = 0 ] || { echo "FAIL: the libRecaulkSystem.dylib program exited $rc"; fail=1; }
[ "$fail" = 0 ] && echo "pselect-signal OK"
exit $fail
