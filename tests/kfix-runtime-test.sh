#!/bin/sh
# platform: host-agnostic -- builds RecaulkKernelFixes.kext, Wowfunhappy's kext and a kevent smoke test; loads them on the 10.9 guest only (RECAULK_TEST_PHASE)
# spec: README.md "The kernel-fixes kext" -- on 10.9.5 13F1911: RecaulkKernelFixes applies kqueue_scan_restart
#       (sysctl 1, an "applied" line), kevent still works with it applied, and it refuses to unload. In a second
#       round Wowfunhappy's KQueueScanContinuePatch, rebuilt from the gist, patches the kernel first, and
#       RecaulkKernelFixes reports it as already applied (sysctl 2) and writes nothing. Each round wants a fresh
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
  # spec: README.md "The kernel-fixes kext" -- his kext, built unchanged from the gist, for the foreign round
  VERSION=$V KEXT_SRC=tests/kext/wowfunhappy KEXT_NAME=KQueueScanContinuePatch sh build/build-kext.sh "$O/wow" \
    > "$O/wow.log" 2>&1 || { echo "FAIL: his kext did not build:"; sed 's/^/    | /' "$O/wow.log"; exit 1; }
fi
runtime_half
[ "${RECAULK_KEXT_LOAD:-}" = 1 ] || { echo "kfix-runtime-test: loads kexts, so runs only where RECAULK_KEXT_LOAD=1 (the on-mavericks guest)"; exit 77; }
sudo -n true || { echo "FAIL: loading kexts needs root, and sudo asks for a password"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }
B=dev.mavergreen.recaulk.kernelfixes
d="$(mktemp -d "${TMPDIR:-/tmp}/kfix-runtime.XXXXXX")"
# platform: kextd refuses a kext not owned by root
sudo -n cp -R "$O/kfix/RecaulkKernelFixes.kext" "$d/"
sudo -n chown -R root:wheel "$d/RecaulkKernelFixes.kext"
trap 'sudo -n rm -rf "$d"' EXIT
loaded() { kextstat -l -b "$1" | grep -q "$1"; }
n=0
mark() { n=$((n + 1)); sudo -n dmesg > "$d/dmesg.$n"; echo "$n"; }
since() { sudo -n dmesg | awk -v f="$d/dmesg.$1" 'BEGIN { while ((getline l < f) > 0) seen[l]++ } { if (seen[$0] > 0) seen[$0]--; else print }'; }
st() { sysctl -n debug.recaulk_kfix.kqueue_scan_restart 2>/dev/null || echo absent; }

case "${RECAULK_KFIX_ROUND:-fresh}" in
fresh)
  # spec: README.md "The kernel-fixes kext" -- the pkg's postinstall loads its LaunchDaemon, which loads the
  #       installed kext; on a guest whose install did not, this loads it the same way
  if ! loaded $B; then
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
  if sudo -n kextunload -b $B > "$d/unload.log" 2>&1; then bad "unload_refused: kextunload succeeded with a fix applied"; fi
  loaded $B || bad "unload_refused: the kext is gone"
  [ "$(st)" = 1 ] || bad "unload_refused: the sysctl is $(st) after the unload attempt"
  ;;
foreign)
  loaded $B && { echo "FAIL: RecaulkKernelFixes is already loaded; the foreign round wants a fresh boot without it"; exit 1; }
  sudo -n cp -R "$O/wow/KQueueScanContinuePatch.kext" "$d/"
  sudo -n chown -R root:wheel "$d/KQueueScanContinuePatch.kext"
  sudo -n kextload "$d/KQueueScanContinuePatch.kext" > "$d/wow.log" 2>&1 || bad "his kext would not load: $(cat "$d/wow.log")"
  m="$(mark)"
  sudo -n kextload "$d/RecaulkKernelFixes.kext" > "$d/load.log" 2>&1 || bad "kextload failed: $(cat "$d/load.log")"
  [ "$(st)" = 2 ] || bad "foreign_patch: the sysctl is $(st), want 2"
  since "$m" | grep -q 'kqueue_scan_restart: already applied (by another kext)' || bad "foreign_patch: no 'already applied' line"
  # spec: README.md "The kernel-fixes kext" -- with nothing of its own applied, it may stop
  sudo -n kextunload -b $B > "$d/unload.log" 2>&1 || bad "foreign_patch: with nothing applied by it, it would not unload: $(cat "$d/unload.log")"
  ;;
*) echo "FAIL: RECAULK_KFIX_ROUND is fresh or foreign"; exit 1 ;;
esac
[ "$fail" = 0 ] && echo "kfix-runtime-test OK (${RECAULK_KFIX_ROUND:-fresh})"
exit $fail
