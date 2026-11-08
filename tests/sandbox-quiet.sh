#!/bin/sh
# platform: host-agnostic -- builds x86_64 programs against librecaulk.a and libRecaulkSystem.dylib; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: src/xnu_version.h -- a Recaulk entry point called first inside a (deny default) sandbox makes no
#       request the sandbox denies: each denial is reported to sandboxd, which launchd then starts
#       (packer, 2026-11-07: OpenSSH's sshd-auth, through pselect). A denied sysctl is the control that
#       the log shows denials; sandboxd logs a process's denials in order, so once the control after a
#       case shows, any denial the case made would show too.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
cc() { "$CC" $FLAGS -arch x86_64 -isystem "$T/include/recaulk" -Wall -Wextra -Werror "$@"; }
if compiling; then
  cc tests/c/sandbox_quiet.c "$T/lib/librecaulk.a" -o "$(tbin sbxq-static)"
  cc tests/c/sandbox_quiet.c -L"$T/lib" -lRecaulkSystem -o "$(tbin sbxq-dylib)"
  check_loads "$(tbin sbxq-static)" "$(tbin sbxq-dylib)"
fi
runtime_half
L=/var/log/system.log
[ -r "$L" ] || { echo "FAIL: cannot read $L, where sandboxd logs denials"; exit 1; }
fail=0
denials() { grep -F "$1($2) deny" "$L" || :; }
# platform: sandboxd logs through syslogd, asynchronously; 30 s is far beyond the second it takes on 10.9
wait_for() {
  _n=0
  while [ -z "$(denials "$1" "$2")" ]; do
    _n=$((_n + 1)); [ "$_n" -le 30 ] || return 1
    sleep 1
  done
}
for p in sbxq-static sbxq-dylib; do
  for c in none pselect forwarded available; do
    # platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it is set where the program is exec'd
    out=$(DYLD_LIBRARY_PATH="$T/lib" "$(tbin $p)" "$c") || { echo "FAIL: $p $c exited $?"; fail=1; continue; }
    pid=${out%% *}
    ctl=$(DYLD_LIBRARY_PATH="$T/lib" "$(tbin $p)" denied) || { echo "FAIL: $p's control exited $?"; fail=1; continue; }
    cpid=${ctl%% *}
    wait_for "$p" "$cpid" || { echo "FAIL: $p's denied control never reached $L, so the log proves nothing"; fail=1; continue; }
    d=$(denials "$p" "$pid")
    if [ -n "$d" ]; then echo "FAIL: $p $c made a request the sandbox denied: $d"; fail=1
    else echo "ok $p $c: no denial"; fi
  done
done
[ "$fail" = 0 ] && echo "sandbox-quiet OK"
exit $fail
