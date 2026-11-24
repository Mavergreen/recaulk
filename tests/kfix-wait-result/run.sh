#!/bin/sh
# platform: macOS-only -- runs as root on a disposable 10.9.5 13F1911 guest, from the copied kit, to prove wait_result_prepost
# spec: README.md "The kernel-fixes kext" -- usage: sudo sh run.sh STEP; the kit's README.md says which steps, in
#       which boot. Every step prints PASS, FAIL, EXPECTED, INCONCLUSIVE or INFO lines that can be relayed as they are.
#       It writes only inside the kit directory, which must be a copy under /var/tmp.
set -u
KIT="$(cd "$(dirname "$0")" && pwd -P)"
ST="$KIT/state"
BIN="$KIT/kfix_wait_result"
KB=dev.mavergreen.recaulk.kernelfixes
UUID13F1911=8926E512-6714-34FC-B27C-6AE90EB51D5E
# spec: README.md "The kernel-fixes kext" -- 13F1911's unslid _kqueue_scan (kqueue_scan_continue is inside it) and
#       _kevent/_kevent64, from /mach_kernel's symbols, for telling the bug's panic from any other
KQ_LO=0xffffff80005c71c0 KQ_HI=0xffffff80005c7ae0 KE_LO=0xffffff80005c6490 KE_HI=0xffffff80005c69a0
# spec: kit README.md "Timing" -- defaults sized for an emulated (TCG) guest; each can be overridden
SECONDS_STRESS="${KFIX_WR_SECONDS:-120}"
ITER_WIDE="${KFIX_WR_ITERATIONS:-20}"
DELAY_WIDE="${KFIX_WR_DELAY_US:-10000}"
CHILL_NS="${KFIX_WR_CHILL_NS:-40000000}"
RANDOM_US="${KFIX_WR_RANDOM_US:-1000}"

say() { echo "$*"; }
verdict() { # verdict PASS|FAIL|EXPECTED|INCONCLUSIVE|INFO STEP: text
  say "$1 $2"
}
sysv() { sysctl -n "debug.recaulk_kfix.$1" 2>/dev/null || echo absent; }
config() {
  q="$(sysv kqueue_scan_restart)" w="$(sysv wait_result_prepost)"
  case "$q:$w" in
    absent:absent) echo nofix ;;
    1:0) echo backstop ;;
    1:1) echo both ;;
    *) echo "unknown(kqueue_scan_restart=$q,wait_result_prepost=$w)" ;;
  esac
}
need_root() { [ "$(id -u)" = 0 ] || { say "FAIL $1: run it as root (sudo sh run.sh $1)"; exit 1; }; }
field() { sed -n "s/.* $1=\\([^ ]*\\).*/\\1/p"; }

guard_location() {
  case "$KIT" in
    /private/var/tmp/*|/var/tmp/*) ;;
    *) say "FAIL location: the kit is at $KIT; copy it to /var/tmp first (README step 1). It never runs from the share."; exit 1 ;;
  esac
  mkdir -p "$ST"
}

# spec: kit README.md "What each step needs" -- the probe the widened steps use must exist and fire
dtrace_ok() {
  [ -f "$ST/dtrace.ok" ]
}

run_plain() { # run_plain MODE ITERATIONS DELAY SECONDS
  "$BIN" "$1" "$2" "$3" "$4" 2>&1 | tee "$ST/$1-plain.$(config).log" | grep '^RESULT\|^ERROR'
}

widen_script() { # the D program: the window, the fast path's wait_result, and nothing else
  cat <<EOF
syscall::kevent:entry /pid == \$target && arg5 == 0/ { self->arm = 1; }
syscall::kevent:return /self->arm/ { self->arm = 0; }
fbt::wait_queue_assert_wait_with_leeway:entry /self->arm && $1 > 0/ { self->arm = 0; @w = count(); chill($1); }
fbt::wait_queue_assert_wait_with_leeway:return /pid == \$target && arg1 == 0/ { @fast[*(int *)((uintptr_t)curthread + 0x58)] = count(); }
END { printa("WINDOWS %@d\\n", @w); printa("FASTPATH wait_result=%d count=%@d\\n", @fast); }
EOF
}

run_dtrace() { # run_dtrace MODE ITERATIONS DELAY SECONDS CHILL_NS
  widen_script "$5" > "$ST/widen.d"
  dtrace -w -q -s "$ST/widen.d" -c "$BIN $1 $2 $3 $4" > "$ST/$1-dtrace.$(config).log" 2>&1
  grep '^RESULT\|^ERROR\|^WINDOWS\|^FASTPATH\|dtrace:' "$ST/$1-dtrace.$(config).log"
}

fastpath_summary() { # from a dtrace log: hits and stale (wait_result != 0) counts
  awk '/^FASTPATH/ { split($2, a, "="); split($3, b, "="); h += b[2]; if (a[2] != 0) s += b[2] }
       END { printf "%d %d\n", h, s }' "$1"
}

mark_panic() { # before a step that may panic: what reports exist, and which step
  ls /Library/Logs/DiagnosticReports/Kernel_*.panic 2>/dev/null > "$ST/panics.before"
  echo "$1 $(config)" > "$ST/panic.step"
  sync
}

step_preflight() {
  need_root preflight; guard_location
  u="$(sysctl -n kern.uuid 2>/dev/null)"
  [ "$u" = "$UUID13F1911" ] && verdict PASS "preflight: kernel UUID $u is 13F1911's" \
    || { verdict FAIL "preflight: kernel UUID is $u, want $UUID13F1911 (13F1911); every fix here is that kernel's"; exit 1; }
  n="$(sysctl -n hw.ncpu)"
  [ "$n" -ge 2 ] && verdict PASS "preflight: $n CPUs" || verdict FAIL "preflight: $n CPU; the race needs 2 or more"
  if kextstat -l | grep -q wowfunhappy.KQueueScanContinuePatch; then
    verdict FAIL "preflight: Wowfunhappy's KQueueScanContinuePatch is loaded, so this boot is not unfixed; remove it and reboot"
  else verdict PASS "preflight: Wowfunhappy's KQueueScanContinuePatch is not loaded"; fi
  verdict INFO "preflight: configuration this boot: $(config)"
  [ -x "$BIN" ] && verdict PASS "preflight: the reproducer is here" || verdict FAIL "preflight: $BIN is missing"
  command -v dtrace > /dev/null && verdict PASS "preflight: dtrace is here" || verdict FAIL "preflight: no dtrace"
  pkgutil --pkg-info dev.mavergreen.recaulk 2>/dev/null | sed -n 's/^version: //p' > "$ST/recaulk.version"
  verdict INFO "preflight: Recaulk pkg installed: $(cat "$ST/recaulk.version"); kexts: $(kextstat -l | awk '{print $6"@"$7}' | grep -i -e mavergreen -e fuse | tr '\n' ' ')"
}

step_dtrace_check() {
  need_root dtrace-check; guard_location
  rm -f "$ST/dtrace.ok"
  if ! dtrace -l -n 'fbt::wait_queue_assert_wait_with_leeway:entry' > /dev/null 2>&1; then
    verdict INCONCLUSIVE "dtrace-check: fbt::wait_queue_assert_wait_with_leeway does not exist here; skip the -dtrace steps and rely on the plain ones"
    return
  fi
  out="$(dtrace -q -n 'fbt::wait_queue_assert_wait_with_leeway:entry /pid == $target/ { @n = count(); } END { printa("FIRED %@d\n", @n); }' \
    -c "$BIN silent 3 -$RANDOM_US 20" 2>&1)"
  c="$(printf '%s\n' "$out" | sed -n 's/^FIRED //p')"
  if [ -n "$c" ] && [ "$c" -gt 0 ]; then
    touch "$ST/dtrace.ok"
    verdict PASS "dtrace-check: the probe exists and fired $c times for the reproducer"
  else
    verdict INCONCLUSIVE "dtrace-check: the probe never fired ($out); skip the -dtrace steps and rely on the plain ones"
  fi
}

step_load() {
  need_root load; guard_location
  want="$1"
  [ "$(config)" = nofix ] || { verdict FAIL "load-$want: this boot already has $(config); reboot first"; exit 1; }
  rm -rf "$ST/kext"; mkdir -p "$ST/kext"
  cp -R "$KIT/kext-$want/RecaulkKernelFixes.kext" "$ST/kext/"
  chown -R root:wheel "$ST/kext"; chmod -R go-w "$ST/kext"
  kextload "$ST/kext/RecaulkKernelFixes.kext" > "$ST/load-$want.log" 2>&1 \
    || { verdict FAIL "load-$want: kextload failed: $(cat "$ST/load-$want.log")"; exit 1; }
  got="$(config)"
  [ "$got" = "$want" ] && verdict PASS "load-$want: configuration is $got" \
    || verdict FAIL "load-$want: configuration is $got, want $want: $(dmesg | grep 'RecaulkKernelFixes:' | tail -4 | tr '\n' ' ')"
  verdict INFO "load-$want: $(dmesg | grep 'RecaulkKernelFixes:' | tail -4 | tr '\n' '|')"
}

step_silent_plain() {
  need_root silent-plain; guard_location
  c="$(config)"; r="$(run_plain silent 1000000000 "-$RANDOM_US" "$SECONDS_STRESS")"
  say "INFO silent-plain ($c): $r"
  z="$(printf '%s\n' "$r" | field zero)" i="$(printf '%s\n' "$r" | field eintr)" n="$(printf '%s\n' "$r" | field iterations)"
  [ -n "$n" ] || { verdict FAIL "silent-plain: the reproducer did not finish: $r"; return; }
  case "$c" in
    both) [ "$z" = 0 ] && [ "$i" = 0 ] && verdict PASS "silent-plain (both): 0 of $n untimed kevents returned 0 or EINTR" \
            || verdict FAIL "silent-plain (both): $z returned 0 events and $i EINTR, of $n; want none" ;;
    nofix|backstop)
      if [ "$z" -gt 0 ] || [ "$i" -gt 0 ]; then verdict EXPECTED "silent-plain ($c): the bug, without DTrace: $z of $n untimed kevents returned 0 events, $i EINTR"
      else verdict INCONCLUSIVE "silent-plain ($c): no stale return in $n tries without DTrace; the -dtrace step widens the window"; fi ;;
    *) verdict FAIL "silent-plain: configuration $c" ;;
  esac
}

step_silent_dtrace() {
  need_root silent-dtrace; guard_location
  dtrace_ok || { verdict INCONCLUSIVE "silent-dtrace: skipped, dtrace-check did not pass"; return; }
  c="$(config)"; r="$(run_dtrace silent "$ITER_WIDE" "$DELAY_WIDE" 600 "$CHILL_NS")"
  say "INFO silent-dtrace ($c): $(printf '%s\n' "$r" | tr '\n' '|')"
  set -- $(fastpath_summary "$ST/silent-dtrace.$c.log")
  hits="$1" stale="$2"
  z="$(printf '%s\n' "$r" | field zero)" n="$(printf '%s\n' "$r" | field iterations)" e="$(printf '%s\n' "$r" | field events)"
  [ -n "$n" ] || { verdict FAIL "silent-dtrace: the reproducer did not finish: $r"; return; }
  [ "$hits" -gt 0 ] || { verdict INCONCLUSIVE "silent-dtrace ($c): the message never landed in the window (0 fast-path waits); raise KFIX_WR_CHILL_NS or lower KFIX_WR_DELAY_US"; return; }
  case "$c" in
    both) [ "$z" = 0 ] && [ "$e" = "$n" ] && [ "$stale" = 0 ] \
            && verdict PASS "silent-dtrace (both): $hits fast-path waits, every one stored wait_result 0; $e of $n kevents returned the event" \
            || verdict FAIL "silent-dtrace (both): $z of $n returned 0 events, $stale of $hits fast-path waits left a stale wait_result" ;;
    nofix|backstop) [ "$z" -gt 0 ] && [ "$stale" -gt 0 ] \
            && verdict EXPECTED "silent-dtrace ($c): the bug: $stale of $hits fast-path waits left a stale wait_result; $z of $n untimed kevents returned 0 events" \
            || verdict FAIL "silent-dtrace ($c): $hits fast-path waits ($stale stale) but $z of $n returned 0 events; want the bug shown" ;;
    *) verdict FAIL "silent-dtrace: configuration $c" ;;
  esac
}

step_probe() {
  need_root probe; guard_location
  dtrace_ok || { verdict INCONCLUSIVE "probe: skipped, dtrace-check did not pass"; return; }
  c="$(config)"; r="$(run_dtrace silent 1000000000 "-$RANDOM_US" "$SECONDS_STRESS" 0)"
  say "INFO probe ($c): $(printf '%s\n' "$r" | tr '\n' '|')"
  set -- $(fastpath_summary "$ST/silent-dtrace.$c.log")
  cp "$ST/silent-dtrace.$c.log" "$ST/probe.$c.log"
  case "$c:$1:$2" in
    *:0:*) verdict INCONCLUSIVE "probe ($c): no fast-path wait in ${SECONDS_STRESS}s without widening" ;;
    both:*:0) verdict PASS "probe (both): all $1 fast-path waits stored wait_result 0" ;;
    both:*) verdict FAIL "probe (both): $2 of $1 fast-path waits left a stale wait_result" ;;
    *:*:0) verdict INCONCLUSIVE "probe ($c): $1 fast-path waits, none stale this time" ;;
    *) verdict EXPECTED "probe ($c): $2 of $1 fast-path waits left a stale wait_result (the bug, seen directly)" ;;
  esac
}

restart_verdict() { # restart_verdict STEP RESULT-LINE
  c="$(config)"
  eb="$(printf '%s\n' "$2" | field ebadf)" z="$(printf '%s\n' "$2" | field zero)" n="$(printf '%s\n' "$2" | field iterations)"
  [ -n "$n" ] || { verdict FAIL "$1: the reproducer did not finish: $2"; return; }
  case "$c" in
    nofix) rm -f "$ST/panic.step"; verdict INCONCLUSIVE "$1 (nofix): no panic in $n primed tries" ;;
    backstop) if [ "$eb" -gt 0 ]; then
                if dmesg | grep -q 'invalid wait_result (3)'; then verdict EXPECTED "$1 (backstop): $eb of $n kevents failed EBADF where the kernel would panic, and it logged the panic's message"
                else verdict FAIL "$1 (backstop): $eb EBADF but no 'invalid wait_result (3)' line in dmesg"; fi
              else verdict INCONCLUSIVE "$1 (backstop): no EBADF in $n primed tries"; fi ;;
    both) [ "$eb" = 0 ] && [ "$z" = 0 ] && ! dmesg | grep -q 'invalid wait_result' \
            && verdict PASS "$1 (both): $n primed tries, no EBADF, no 0-event return, the backstop never fired" \
            || verdict FAIL "$1 (both): $eb EBADF, $z 0-event returns of $n; dmesg: $(dmesg | grep 'invalid wait_result' | tail -1)" ;;
  esac
}

step_restart_plain() {
  need_root restart-plain; guard_location
  [ "$(config)" = nofix ] && { mark_panic restart-plain; say "INFO restart-plain (nofix): this should panic the guest; reset it and run classify"; }
  r="$(run_plain restart 1000000000 "-$RANDOM_US" "$SECONDS_STRESS")"
  say "INFO restart-plain ($(config)): $r"
  restart_verdict restart-plain "$r"
}

step_restart_dtrace() {
  need_root restart-dtrace; guard_location
  dtrace_ok || { verdict INCONCLUSIVE "restart-dtrace: skipped, dtrace-check did not pass"; return; }
  [ "$(config)" = nofix ] && { mark_panic restart-dtrace; say "INFO restart-dtrace (nofix): this should panic the guest; reset it and run classify"; }
  r="$(run_dtrace restart "$ITER_WIDE" "$DELAY_WIDE" 600 "$CHILL_NS")"
  say "INFO restart-dtrace ($(config)): $(printf '%s\n' "$r" | tr '\n' '|')"
  restart_verdict restart-dtrace "$(printf '%s\n' "$r" | grep '^RESULT')"
}

in_range() { # in_range ADDR LO HI, kernel addresses (negative as 64-bit signed, so compare as such)
  [ $(($1)) -ge $(($2)) ] && [ $(($1)) -lt $(($3)) ]
}

step_classify() {
  need_root classify; guard_location
  [ -f "$ST/panic.step" ] || { verdict FAIL "classify: no step marked a panic to classify"; return; }
  set -- $(cat "$ST/panic.step"); s="$1" cfg="$2"
  f="" t=0
  while [ -z "$f" ] && [ "$t" -lt 120 ]; do
    f="$(ls -t /Library/Logs/DiagnosticReports/Kernel_*.panic 2>/dev/null | grep -vxF -f "$ST/panics.before" | head -1)"
    [ -n "$f" ] || { sleep 5; t=$((t + 5)); }
  done
  if [ -z "$f" ]; then
    p="$(nvram aapl,panic-info 2>/dev/null | head -c 200)"
    verdict INCONCLUSIVE "classify ($s, $cfg): no new panic report after ${t}s${p:+ (NVRAM holds panic info: $p)}; read the console's panic text instead"
    return
  fi
  cp "$f" "$ST/"
  slide="$(sed -n 's/^Kernel slide: *\(0x[0-9a-fA-F]*\).*/\1/p' "$f" | head -1)"
  msg=0; grep -q 'kqueue_scan_continue: - invalid wait_result (3)' "$f" && msg=1
  kq=0 ke=0
  for a in $(sed -n 's/^0x[0-9a-f]* : \(0x[0-9a-f]*\).*/\1/p' "$f"); do
    u=$(( a - ${slide:-0} ))
    in_range $u $KQ_LO $KQ_HI && kq=$((kq + 1))
    in_range $u $KE_LO $KE_HI && ke=$((ke + 1))
  done
  verdict INFO "classify ($s, $cfg): $f: $(grep -m1 '^panic(' "$f" | cut -c1-200); slide $slide; $kq frames in kqueue_scan, $ke in kevent"
  if [ "$msg" = 1 ] && [ "$kq" -gt 0 ]; then
    verdict EXPECTED "classify ($s, $cfg): ours, the bug's panic: 'invalid wait_result (3)' from kqueue_scan_continue"
    rm -f "$ST/panic.step"
  else
    verdict INCONCLUSIVE "classify ($s, $cfg): probe-induced or unrelated (message $msg, kqueue_scan frames $kq); this run proves nothing"
    rm -f "$ST/panic.step"
  fi
}

step_cleanup() {
  need_root cleanup
  if kextstat -l -b $KB | grep -q $KB; then verdict FAIL "cleanup: the test kext is still loaded; reboot first, then run cleanup"; exit 1; fi
  verdict PASS "cleanup: no RecaulkKernelFixes loaded"
  v="$(pkgutil --pkg-info dev.mavergreen.recaulk 2>/dev/null | sed -n 's/^version: //p')"
  [ -z "$v" ] || [ ! -f "$ST/recaulk.version" ] || [ "$v" = "$(cat "$ST/recaulk.version")" ] \
    && verdict PASS "cleanup: Recaulk pkg $v as installed" || verdict FAIL "cleanup: Recaulk pkg is $v, was $(cat "$ST/recaulk.version")"
  verdict INFO "cleanup: kexts: $(kextstat -l | awk '{print $6"@"$7}' | grep -i -e mavergreen -e fuse | tr '\n' ' ')"
  case "$KIT" in
    /private/var/tmp/kfix-wr|/var/tmp/kfix-wr) cd / && rm -rf "$KIT" && verdict PASS "cleanup: removed $KIT" ;;
    *) verdict INFO "cleanup: left $KIT (remove it by hand)" ;;
  esac
}

case "${1:-}" in
  preflight) step_preflight ;;
  dtrace-check) step_dtrace_check ;;
  load-backstop) step_load backstop ;;
  load-both) step_load both ;;
  config) say "INFO config: $(config)" ;;
  silent-plain) step_silent_plain ;;
  silent-dtrace) step_silent_dtrace ;;
  probe) step_probe ;;
  restart-plain) step_restart_plain ;;
  restart-dtrace) step_restart_dtrace ;;
  classify) step_classify ;;
  cleanup) step_cleanup ;;
  *) say "usage: sudo sh run.sh preflight|dtrace-check|load-backstop|load-both|config|silent-plain|silent-dtrace|probe|restart-plain|restart-dtrace|classify|cleanup"; exit 2 ;;
esac
