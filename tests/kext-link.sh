#!/bin/sh
# platform: host-agnostic -- links RecaulkKPI.kext with cctools' ld64 on any host; asks 10.9's kxld to link it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "The kernel back-fill kext" -- 10.9's kxld loads an x86_64 kext only as MH_KEXT_BUNDLE without
#       stubs or dyld bind opcodes (xnu-2422.115.4 libkern/kxld/kxld_object.c), which only ld64 -kext writes;
#       the binary defines, as externals, exactly the objects' 8 names
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/kext.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
O="$(dirname "$(tbin x)")/build"
K="$O/RecaulkKPI.kext"
if compiling; then
  rm -rf "$O"
  mkdir -p "$O"
  kext_build "$O"
  bin="$K/Contents/MacOS/RecaulkKPI"
  [ -f "$bin" ] || { echo "FAIL: build/build-kext.sh linked no $bin"; exit 1; }
  # platform: mach_header_64 filetype 0xb is MH_KEXT_BUNDLE
  "$OTOOL" -hv "$bin" | grep -q 'KEXTBUNDLE' || bad "the binary is not MH_KEXT_BUNDLE: $("$OTOOL" -hv "$bin" | tail -1)"
  "$OTOOL" -l "$bin" | grep -qE 'LC_DYLD_INFO|LC_LOAD_DYLINKER' && bad "the binary carries dyld load commands, which kxld never applies"
  "$NM" -m "$bin" | grep -q 'dyld_stub_binder' && bad "the binary imports dyld_stub_binder"
  "$NM" -m "$bin" | awk '/ external / && !/private external/ && !/undefined/ { print $NF }' | LC_ALL=C sort -u > "$O/got"
  printf '%s\n' ___memcpy_chk ___strncpy_chk _buf_map_range _buf_unmap_range _kmod_info _ubc_upl_map_range \
    _vfs_get_notify_attributes _vnode_notify | LC_ALL=C sort > "$O/want"
  cmp -s "$O/want" "$O/got" || bad "the linked binary's exports differ (< missing, > extra): $(diff "$O/want" "$O/got" | grep '^[<>]' | tr '\n' ' ')"
fi
runtime_half
# platform: kextutil -n links without loading and needs no root; -a places the kext where kxld would, -k the
#           kernel it links against, -r the libraries it resolves from
out="$(kextutil -n -e -r /System/Library/Extensions -arch x86_64 -k /mach_kernel \
  -a dev.mavergreen.recaulk.kpi@0xffffff7f80a00000 -s "$O" "$K" 2>&1)" || bad "kxld would not link it: $out"
[ "$fail" = 0 ] && echo "kext-link OK"
exit $fail
