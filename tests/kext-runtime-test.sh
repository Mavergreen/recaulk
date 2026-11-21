#!/bin/sh
# platform: host-agnostic -- builds RecaulkKPI.kext's test variants, the probe kext and a kqueue reconciler; loads them on the 10.9 guest only (RECAULK_TEST_PHASE)
# spec: README.md "The kernel back-fill kext" -- on 10.9, with the pkg's /Library/Extensions/RecaulkKPI.kext:
#       a cold load through a dependent kext, twice (the second after kextcache -system-caches); vnode_notify
#       forwarded and delivered to kqueue (decision E's reconciliation, 50 trials); the *_range calls read the
#       file's bytes; the _chk copies; unload in dependency order; a build gated to Darwin 14 refuses with its
#       line; a build pointed at a file that is not the kernel logs FALLBACK, still loads, and delivers nothing.
#       Loading kexts needs RECAULK_KEXT_LOAD=1, which only the on-mavericks job's disposable guest sets.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/kext.sh
O="$(dirname "$(tbin x)")"
if compiling; then
  rm -rf "$O/probe" "$O/gate14" "$O/fallback"
  VERSION=20261121.7 KEXT_SRC=tests/kext/probe KEXT_NAME=RecaulkKPIProbe sh build/build-kext.sh "$O/probe" > "$O/probe.log" 2>&1 \
    || { echo "FAIL: the probe kext did not build:"; sed 's/^/    | /' "$O/probe.log"; exit 1; }
  VERSION=20261121.7 KEXT_CFLAGS=-DRECAULK_KPI_DARWIN_MAJOR=14 sh build/build-kext.sh "$O/gate14" > "$O/gate14.log" 2>&1 \
    || { echo "FAIL: the Darwin 14 variant did not build:"; sed 's/^/    | /' "$O/gate14.log"; exit 1; }
  VERSION=20261121.7 KEXT_CFLAGS='-DRECAULK_KPI_KERNEL_PATH="/usr/lib/dyld"' sh build/build-kext.sh "$O/fallback" > "$O/fallback.log" 2>&1 \
    || { echo "FAIL: the fallback variant did not build:"; sed 's/^/    | /' "$O/fallback.log"; exit 1; }
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror tests/c/kext_notify_watch.c -o "$(tbin watch)"
  check_loads "$(tbin watch)"
fi
runtime_half
[ "${RECAULK_KEXT_LOAD:-}" = 1 ] || { echo "kext-runtime-test: loads kexts, so runs only where RECAULK_KEXT_LOAD=1 (the on-mavericks guest)"; exit 77; }
sudo -n true || { echo "FAIL: loading kexts needs root, and sudo asks for a password"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
K=/Library/Extensions/RecaulkKPI.kext
[ -d "$K" ] || { echo "FAIL: the pkg installed no $K"; exit 1; }
d="$(mktemp -d "${TMPDIR:-/tmp}/kext-runtime.XXXXXX")"
# platform: kextd refuses a kext not owned by root, so each loose kext is copied root:wheel first
for k in probe/RecaulkKPIProbe gate14/RecaulkKPI fallback/RecaulkKPI; do
  mkdir -p "$d/${k%/*}"
  sudo -n cp -R "$O/$k.kext" "$d/${k%/*}/"
  sudo -n chown -R root:wheel "$d/$k.kext"
done
P="$d/probe/RecaulkKPIProbe.kext"
cleanup() {
  sudo -n kextunload -b dev.mavergreen.recaulk.test.kpi-probe >/dev/null 2>&1 || :
  sudo -n kextunload -b dev.mavergreen.recaulk.kpi >/dev/null 2>&1 || :
  sudo -n rm -rf "$d"
}
trap cleanup EXIT
loaded() { kextstat -l -b "$1" | grep -q "$1"; }
mark() { sudo -n dmesg | wc -l | tr -d ' '; }
since() { sudo -n dmesg | sed -n "$(( $1 + 1 )),\$p"; }
printf 'recaulk-probe-0123456789\n' > "$d/file"
sync

for round in cold cached; do
  if [ "$round" = cached ]; then sudo -n kextcache -system-caches || bad "kextcache -system-caches failed"; fi
  ! loaded dev.mavergreen.recaulk.kpi || bad "$round: RecaulkKPI was loaded before the probe asked for it"
  m="$(mark)"
  sudo -n kextload "$P" > "$d/load.log" 2>&1 || { bad "$round: kextload of the probe failed: $(cat "$d/load.log")"; break; }
  loaded dev.mavergreen.recaulk.kpi || bad "$round: loading the probe did not load RecaulkKPI from /Library/Extensions"
  loaded dev.mavergreen.recaulk.test.kpi-probe || bad "$round: the probe is not loaded"
  out="$(sudo -n "$(tbin watch)" "$d/file" 50)" || bad "$round: the reconciler failed: $out"
  echo "kext-runtime-test: $round: $(printf '%s\n' "$out" | tail -1)"
  printf '%s\n' "$out" | grep -qx 'delivered [1-9][0-9]*/50 forwarded 50/50' \
    || bad "$round: vnode_notify did not reach the kernel's on every call, or nothing was delivered: $out"
  since "$m" | grep -q 'RecaulkKPI: vnode_notify: forwarding to kernel' || bad "$round: no 'vnode_notify: forwarding to kernel' line"
  since "$m" | grep -q 'RecaulkKPI: vnode_notify: FALLBACK' && bad "$round: the installed kext fell back: $(since "$m" | grep FALLBACK)"
  # platform: the UPL maps only a resident page, so the file is read into the page cache first
  cat "$d/file" > /dev/null
  sudo -n sysctl -w debug.recaulk_kpi_probe.range="$d/file" >/dev/null || bad "$round: the range sysctl failed"
  [ "$(sysctl -n debug.recaulk_kpi_probe.error)" = 0 ] || bad "$round: the *_range calls failed, errno $(sysctl -n debug.recaulk_kpi_probe.error)"
  [ "$(sysctl -n debug.recaulk_kpi_probe.upl_bytes)" = recaulk-probe-01 ] || bad "$round: ubc_upl_map_range read '$(sysctl -n debug.recaulk_kpi_probe.upl_bytes)'"
  [ "$(sysctl -n debug.recaulk_kpi_probe.buf_bytes)" = recaulk-probe-01 ] || bad "$round: buf_map_range read '$(sysctl -n debug.recaulk_kpi_probe.buf_bytes)'"
  [ "$(sysctl -n debug.recaulk_kpi_probe.chk)" = 1 ] || bad "$round: __memcpy_chk or __strncpy_chk copied wrong"
  sudo -n kextunload -b dev.mavergreen.recaulk.kpi >/dev/null 2>&1 && bad "$round: RecaulkKPI unloaded while the probe depends on it"
  sudo -n kextunload -b dev.mavergreen.recaulk.test.kpi-probe || bad "$round: the probe would not unload"
  sudo -n kextunload -b dev.mavergreen.recaulk.kpi || bad "$round: RecaulkKPI would not unload after the probe"
  sysctl debug.recaulk_kpi >/dev/null 2>&1 && bad "$round: debug.recaulk_kpi outlived the unload"
done

m="$(mark)"
sudo -n kextload "$d/gate14/RecaulkKPI.kext" > "$d/gate.log" 2>&1 && bad "the Darwin 14 build loaded on Darwin 13"
since "$m" | grep -q 'RecaulkKPI: not starting: this kernel is Darwin 13' || bad "the Darwin 14 build's refusal logged no 'not starting' line"
loaded dev.mavergreen.recaulk.kpi && bad "the Darwin 14 build stayed loaded"

m="$(mark)"
sudo -n kextload -d "$d/fallback/RecaulkKPI.kext" "$P" > "$d/fb.log" 2>&1 || bad "the fallback build, or the probe on it, did not load: $(cat "$d/fb.log")"
if loaded dev.mavergreen.recaulk.test.kpi-probe; then
  out="$(sudo -n "$(tbin watch)" "$d/file" 3)" || bad "fallback: the reconciler failed: $out"
  printf '%s\n' "$out" | grep -qx 'delivered 0/3 forwarded 0/3' || bad "fallback: something was delivered or forwarded: $out"
  since "$m" | grep -q 'RecaulkKPI: vnode_notify: FALLBACK, delivering nothing' || bad "fallback: no FALLBACK line"
fi
[ "$fail" = 0 ] && echo "kext-runtime-test OK"
exit $fail
