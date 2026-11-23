#!/bin/sh
# platform: host-agnostic -- builds RecaulkKernelFixes.kext on any host; asks 10.9's kxld to link it (kextutil -n, no load) on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "The kernel-fixes kext" -- the second kext is built like RecaulkKPI: an MH_KEXT_BUNDLE exporting
#       only _kmod_info, reproducible, importing only from the 10.9 KPI libraries its Info.plist names (all
#       13.0.0, never com.apple.kpi.private), with no IOKitPersonalities, and sharing no export with RecaulkKPI
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/kext.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
O="$(dirname "$(tbin x)")/kfix-build"
N=RecaulkKernelFixes
K="$O/a/$N.kext"
kf_build() { KEXT_SRC=src/kfix KEXT_NAME=$N kext_build "$@"; }
if compiling; then
  rm -rf "$O"; mkdir -p "$O/b"
  kf_build "$O/a" 20261123.1
  kf_build "$O/b/deeper" 20261123.1
  kext_build "$O/kpi"
  bin="$K/Contents/MacOS/$N"
  [ -f "$bin" ] || { echo "FAIL: build/build-kext.sh linked no $bin"; exit 1; }
  # platform: mach_header_64 filetype 0xb is MH_KEXT_BUNDLE
  "$OTOOL" -hv "$bin" | grep -q 'KEXTBUNDLE' || bad "the binary is not MH_KEXT_BUNDLE"
  "$NM" -m "$bin" | awk '/ external / && !/private external/ && !/undefined/ { print $NF }' | LC_ALL=C sort -u > "$O/got"
  [ "$(cat "$O/got")" = _kmod_info ] || bad "it exports more than _kmod_info: $(tr '\n' ' ' < "$O/got")"
  "$NM" -m "$O/kpi/RecaulkKPI.kext/Contents/MacOS/RecaulkKPI" \
    | awk '/ external / && !/private external/ && !/undefined/ && $NF != "_kmod_info" { print $NF }' | LC_ALL=C sort -u > "$O/kpi-got"
  common="$(LC_ALL=C comm -12 "$O/got" "$O/kpi-got" | tr '\n' ' ')"
  [ -z "$common" ] || bad "it exports what RecaulkKPI exports: $common"
  for f in Contents/Info.plist "Contents/MacOS/$N"; do
    cmp -s "$O/a/$N.kext/$f" "$O/b/deeper/$N.kext/$f" || bad "$f differs between two builds"
  done
  p="$K/Contents/Info.plist"
  want() { got="$(plist "$p" get "$1" || echo '<absent>')"; [ "$got" = "$2" ] || bad "$1 is '$got', want '$2'"; }
  want CFBundleIdentifier dev.mavergreen.recaulk.kernelfixes
  want CFBundleExecutable $N
  want CFBundleVersion 2611.23.1
  plist "$p" get IOKitPersonalities >/dev/null 2>&1 && bad "it has IOKitPersonalities; a LaunchDaemon loads it"
  : > "$O/available"
  for l in $(plist "$p" get OSBundleLibraries); do
    id="${l%%=*}"
    case "$id" in com.apple.kpi.private|com.apple.kpi.unsupported.private) bad "it names $id" ;; com.apple.kpi.*) ;; *) bad "it names $id" ;; esac
    [ "${l#*=}" = 13.0.0 ] || bad "$id is at ${l#*=}, want 13.0.0"
    [ -f "tests/fixtures/kpi-10.9/$id.txt" ] && cat "tests/fixtures/kpi-10.9/$id.txt" >> "$O/available"
  done
  LC_ALL=C sort -u -o "$O/available" "$O/available"
  set -- "$O"/a/obj/*.o
  "$NM" -m "$@" | awk '!/undefined/ { print $NF }' | LC_ALL=C sort -u > "$O/defined"
  # platform: libkmod.a, linked last, supplies _start and _stop
  "$NM" -u "$@" | awk 'NF { print $NF }' | grep -v ':$' | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$O/defined" \
    | grep -vx -e __start -e __stop > "$O/undefined" || true
  # spec: README.md "The kernel-fixes kext" -- kernel text is written with every CPU parked in a rendezvous, never
  #       with only this CPU's interrupts off
  grep -qx _mp_rendezvous_no_intrs "$O/undefined" || bad "it does not write kernel text through mp_rendezvous_no_intrs"
  grep -qx _ml_set_interrupts_enabled "$O/undefined" && bad "it still writes kernel text with only this CPU's interrupts off"
  missing="$(LC_ALL=C comm -23 "$O/undefined" "$O/available" | tr '\n' ' ')"
  [ -z "$missing" ] || bad "imported but no named 10.9 KPI library exports them: $missing"
fi
runtime_half
# platform: kextutil -n links without loading and needs no root (as tests/kext-link.sh)
out="$(kextutil -n -e -r /System/Library/Extensions -arch x86_64 -k /mach_kernel \
  -a dev.mavergreen.recaulk.kernelfixes@0xffffff7f80a00000 -s "$O/a" "$K" 2>&1)" || bad "kxld would not link it: $out"
[ "$fail" = 0 ] && echo "kfix-build OK"
exit $fail
