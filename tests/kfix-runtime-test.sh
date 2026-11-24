#!/bin/sh
# platform: host-agnostic -- builds RecaulkKernelFixes.kext, Wowfunhappy's kext and a kevent smoke test; loads them on the 10.9 guest only (RECAULK_TEST_PHASE)
# spec: README.md "The kernel-fixes kext" -- on 10.9.5 13F1911: RecaulkKernelFixes applies kqueue_scan_restart
#       (sysctl 1, an "applied" line), kevent still works with it applied, signal_target_exit is applied and closes its race (exit_race, below),
#       and it refuses to unload. In a second
#       round Wowfunhappy's KQueueScanContinuePatch, rebuilt from the gist, patches the kernel first, and
#       RecaulkKernelFixes reports it as already applied (sysctl 2) and writes nothing; before that, a build whose
#       table names another kernel's UUID applies nothing and unloads. Each round wants a fresh
#       boot, since a patched kernel stays patched: the guest job reboots between rounds, or runs one round per
#       boot with RECAULK_KFIX_ROUND=fresh|foreign (default fresh).
#       The fresh round also checks that kextd raised no unsigned-kext complaint (no_dialog). Whether the
#       installed LaunchDaemon loads it at boot (boot_load) needs a guest reboot, a manual check for now.
#       Loading kexts needs RECAULK_KEXT_LOAD=1, which only the on-mavericks job's disposable guest sets.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/kext.sh
O="$(dirname "$(tbin x)")"
# spec: README.md "The kernel-fixes kext" -- a version above any release's, which kextload prefers
V=20991231.99
if compiling; then
  rm -rf "$O/kfix"
  VERSION=$V KEXT_SRC=src/kfix KEXT_NAME=RecaulkKernelFixes sh build/build-kext.sh "$O/kfix" > "$O/kfix.log" 2>&1 \
    || { echo "FAIL: RecaulkKernelFixes did not build:"; sed 's/^/    | /' "$O/kfix.log"; exit 1; }
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror tests/c/kfix_kqueue_restart.c -o "$(tbin kq)"
  check_loads "$(tbin kq)"
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror tests/c/kfix_exit_race.c -o "$(tbin exitrace)"
  check_loads "$(tbin exitrace)"
  # spec: README.md "The kernel-fixes kext" -- the test-only gap-widening kext, for exit_race; never shipped
  rm -rf "$O/widen"
  VERSION=$V KEXT_SRC=tests/kext/widen KEXT_NAME=RecaulkKfixWiden sh build/build-kext.sh "$O/widen" > "$O/widen.log" 2>&1 \
    || { echo "FAIL: the gap-widening kext did not build:"; sed 's/^/    | /' "$O/widen.log"; exit 1; }
  # spec: README.md "The kernel-fixes kext" -- a build whose table names another kernel's UUID, for uuid_variant
  rm -rf "$O/kfix-uuid"
  VERSION=$V KEXT_SRC=src/kfix KEXT_NAME=RecaulkKernelFixes KEXT_CFLAGS=-DRECAULK_KFIX_UUID_FLIP sh build/build-kext.sh "$O/kfix-uuid" \
    > "$O/kfix-uuid.log" 2>&1 || { echo "FAIL: the changed-UUID variant did not build:"; sed 's/^/    | /' "$O/kfix-uuid.log"; exit 1; }
  # spec: README.md "The kernel-fixes kext" -- his kext, built unchanged from the gist, for the foreign round
  VERSION=$V KEXT_SRC=tests/kext/wowfunhappy KEXT_NAME=KQueueScanContinuePatch sh build/build-kext.sh "$O/wow" \
    > "$O/wow.log" 2>&1 || { echo "FAIL: his kext did not build:"; sed 's/^/    | /' "$O/wow.log"; exit 1; }
fi
runtime_half
[ "${RECAULK_KEXT_LOAD:-}" = 1 ] || { echo "kfix-runtime-test: loads kexts, so runs only where RECAULK_KEXT_LOAD=1 (the on-mavericks guest)"; exit 77; }
sudo -n true || { echo "FAIL: loading kexts needs root, and sudo asks for a password"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
KB=dev.mavergreen.recaulk.kernelfixes
d="$(mktemp -d "${TMPDIR:-/tmp}/kfix-runtime.XXXXXX")"
# platform: kextd refuses a kext not owned by root
sudo -n cp -R "$O/kfix/RecaulkKernelFixes.kext" "$d/"
sudo -n chown -R root:wheel "$d/RecaulkKernelFixes.kext"
sudo -n cp -R "$O/widen/RecaulkKfixWiden.kext" "$d/"
sudo -n chown -R root:wheel "$d/RecaulkKfixWiden.kext"
sudo -n mkdir "$d/uuid"; sudo -n cp -R "$O/kfix-uuid/RecaulkKernelFixes.kext" "$d/uuid/"
sudo -n chown -R root:wheel "$d/uuid/RecaulkKernelFixes.kext"
# spec: README.md "The kernel-fixes kext" -- the gap-widening kext cannot unload, so whatever happens its delay
#       goes back to 0 for the tests after this one in the same boot
cleanup() { sysctl -n debug.kfixwiden.delay_us > /dev/null 2>&1 && sudo -n sysctl -w debug.kfixwiden.delay_us=0 > /dev/null; sudo -n rm -rf "$d"; }
trap cleanup EXIT
loaded() { kextstat -l -b "$1" | grep -q "$1"; }
n=0
mark() { n=$((n + 1)); sudo -n dmesg > "$d/dmesg.$n"; echo "$n"; }
since() { sudo -n dmesg | awk -v f="$d/dmesg.$1" 'BEGIN { while ((getline l < f) > 0) seen[l]++ } { if (seen[$0] > 0) seen[$0]--; else print }'; }
st() { sysctl -n debug.recaulk_kfix.kqueue_scan_restart 2>/dev/null || echo absent; }

case "${RECAULK_KFIX_ROUND:-fresh}" in
fresh)
  # spec: README.md "The kernel-fixes kext" -- the pkg's postinstall lists the kext in OSKextSigExceptionList at its
  #       version, restarts kextd and loads its LaunchDaemon, which loads the installed kext: on stock 10.9 (no
  #       kext-dev-mode) all of that must work for it to be loaded here. If it is not, load it anyway to test the rest.
  xl=/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist
  pv() { awk -v k="<key>$2</key>" 'index($0, k) { getline; gsub(/.*<string>|<\/string>.*/, ""); print; f = 1; exit } END { if (!f) print "absent" }' "$1" 2>/dev/null; }
  kv="$(pv /Library/Extensions/RecaulkKernelFixes.kext/Contents/Info.plist CFBundleVersion)"
  xv="$(pv "$xl" "$KB")"
  [ "$xv" = "$kv" ] || bad "sig_exception: OSKextSigExceptionList lists $KB at $xv, the installed kext is $kv"
  if ! loaded $KB; then
    bad "loaded_by_install: the pkg's install did not load it: $(grep -i -e kernelfixes -e 'invalid signature' /var/log/system.log | tail -3)"
    sudo -n kextload /Library/Extensions/RecaulkKernelFixes.kext > "$d/load.log" 2>&1 || bad "kextload failed: $(cat "$d/load.log")"
  fi
  [ "$(st)" = 1 ] || bad "applied: debug.recaulk_kfix.kqueue_scan_restart is $(st), want 1"
  sudo -n dmesg | grep -q 'RecaulkKernelFixes: kqueue_scan_restart: applied' || bad "applied: no 'kqueue_scan_restart: applied' line: $(sudo -n dmesg | grep RecaulkKernelFixes)"
  # platform: 10.9's kextd logs an unsigned /Library/Extensions kext's load as "Invalid signature" and puts up a
  #           dialog naming it (kext_tools 10.9, checkKextSignature); none may name this bundle
  if grep -i 'signature' /var/log/system.log 2>/dev/null | grep -q 'RecaulkKernelFixes'; then
    bad "no_dialog: kextd logged a signature complaint: $(grep -i signature /var/log/system.log | grep RecaulkKernelFixes | tail -1)"
  fi
  [ -d /Library/Extensions/RecaulkKernelFixes.kext ] || bad "the pkg installed no /Library/Extensions/RecaulkKernelFixes.kext"
  out="$("$(tbin kq)")" || bad "kqueue_restart: the reproducer failed: $out"
  echo "kfix-runtime-test: kqueue_restart: $out"
  # spec: README.md "The kernel-fixes kext" -- signal_target_exit is applied, and closes its race: the gap-widening
  #       kext delays psignal's thread_abort_safely 5 ms, then classifies the thread it would abort, and in its
  #       mode 0 skips the abort of one already freed. exit_race (the panic's minimal shape) makes 200 picks of a
  #       thread its process's exit is tearing down. Unfixed, most are freed first (182 of 200 on 13F1911; in
  #       mode 1, the panic); fixed, each waits out the signal, so nearly all are still there, exiting. The
  #       counters see every psignal on the box, so they are zeroed first and most picks must be exiting ones.
  #       Mode 0 cannot panic while the fix holds; without it, an abort of a thread freed after its check can.
  sig="$(sysctl -n debug.recaulk_kfix.signal_target_exit 2>/dev/null || echo absent)"
  [ "$sig" = 1 ] || bad "signal_applied: debug.recaulk_kfix.signal_target_exit is $sig, want 1: $(sudo -n dmesg | grep 'RecaulkKernelFixes: signal_target_exit')"
  if [ "$sig" = 1 ]; then
    W=debug.kfixwiden
    # spec: README.md "The kernel-fixes kext" -- on one CPU the thread is never freed in the window, fix or no fix
    #       (13F1911, cpus=1: 0 of up to 47 exiting picks freed, delays 5 to 100 ms), so the check proves nothing
    if [ "$(sysctl -n hw.ncpu)" -lt 2 ]; then
      bad "exit_race: this guest has $(sysctl -n hw.ncpu) CPU; on one, an unfixed kernel passes too (give it 2 or more)"
    elif ! sudo -n kextload "$d/RecaulkKfixWiden.kext" > "$d/widen.log" 2>&1; then
      bad "exit_race: the gap-widening kext would not load: $(cat "$d/widen.log")"
    elif [ "$(sysctl -n $W.mode 2>/dev/null)" != 0 ]; then
      bad "exit_race: the gap-widening kext did not apply: $(sudo -n dmesg | grep RecaulkKfixWiden)"
    else
      for k in picks live exiting reused destroyed; do sudo -n sysctl -w $W.$k=0 > /dev/null || bad "exit_race: cannot zero $W.$k"; done
      sudo -n sysctl -w $W.delay_us=5000 > /dev/null || bad "exit_race: cannot set $W.delay_us"
      "$(tbin exitrace)" 200 || bad "exit_race: the program failed"
      c() { sysctl -n $W.$1 2>/dev/null || echo -1; }
      out="picks=$(c picks) live=$(c live) exiting=$(c exiting) reused=$(c reused) destroyed=$(c destroyed)"
      sudo -n sysctl -w $W.delay_us=0 > /dev/null || true
      echo "kfix-runtime-test: exit_race: $out"
      # spec: README.md "The kernel-fixes kext" -- 200 of 200 were exiting on 13F1911 with the fix; 150 leaves room
      #       for a guest's timing, and still fails a run whose picks mostly missed the race
      [ "$(c exiting)" -ge 150 ] || bad "exit_race: fewer than 150 of 200 aborts hit an exiting thread, so the race was barely entered: $out"
      [ "$(c destroyed)" = 0 ] && [ "$(c reused)" = 0 ] || bad "exit_race: an abort hit a freed thread: $out"
    fi
  fi
  if sudo -n kextunload -b $KB > "$d/unload.log" 2>&1; then bad "unload_refused: kextunload succeeded with a fix applied"; fi
  loaded $KB || bad "unload_refused: the kext is gone"
  [ "$(st)" = 1 ] || bad "unload_refused: the sysctl is $(st) after the unload attempt"
  ;;
foreign)
  loaded $KB && { echo "FAIL: RecaulkKernelFixes is already loaded; the foreign round wants a fresh boot without it"; exit 1; }
  # spec: README.md "The kernel-fixes kext" -- uuid_variant: a kernel the table does not name gets no fix, one line,
  #       and the kext, having applied nothing, unloads
  m="$(mark)"
  sudo -n kextload "$d/uuid/RecaulkKernelFixes.kext" > "$d/uuid.log" 2>&1 || bad "uuid_variant: kextload failed: $(cat "$d/uuid.log")"
  [ "$(st)" = 0 ] || bad "uuid_variant: the sysctl is $(st), want 0"
  since "$m" | grep -q 'RecaulkKernelFixes: no fixes for this kernel (UUID ' || bad "uuid_variant: no 'no fixes for this kernel' line"
  sudo -n kextunload -b $KB > "$d/unload.log" 2>&1 || bad "uuid_variant: it would not unload: $(cat "$d/unload.log")"
  sudo -n cp -R "$O/wow/KQueueScanContinuePatch.kext" "$d/"
  sudo -n chown -R root:wheel "$d/KQueueScanContinuePatch.kext"
  sudo -n kextload "$d/KQueueScanContinuePatch.kext" > "$d/wow.log" 2>&1 || bad "his kext would not load: $(cat "$d/wow.log")"
  m="$(mark)"
  sudo -n kextload "$d/RecaulkKernelFixes.kext" > "$d/load.log" 2>&1 || bad "kextload failed: $(cat "$d/load.log")"
  [ "$(st)" = 2 ] || bad "foreign_patch: the sysctl is $(st), want 2"
  since "$m" | grep -q 'kqueue_scan_restart: already applied (by another kext)' || bad "foreign_patch: no 'already applied' line"
  # spec: README.md "The kernel-fixes kext" -- with nothing of its own applied, it may stop
  sudo -n kextunload -b $KB > "$d/unload.log" 2>&1 || bad "foreign_patch: with nothing applied by it, it would not unload: $(cat "$d/unload.log")"
  ;;
*) echo "FAIL: RECAULK_KFIX_ROUND is fresh or foreign"; exit 1 ;;
esac
[ "$fail" = 0 ] && echo "kfix-runtime-test OK (${RECAULK_KFIX_ROUND:-fresh})"
exit $fail
