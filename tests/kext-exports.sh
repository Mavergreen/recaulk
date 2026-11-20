#!/bin/sh
# platform: host-agnostic -- reads the kext's clang22-built objects with llvm-nm
# spec: README.md "The kernel back-fill kext" -- the objects define, as globals, exactly the 7 names macFUSE 5.5.0
#       imports and 10.9's public KPIs lack, plus _kmod_info, which the kernel's loader reads; everything else
#       (sysctl nodes, the once-lock, the parser) stays private
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/kext.sh
d="$(mktemp -d "${TMPDIR:-/tmp}/kext-exports.XXXXXX")"
trap 'rm -rf "$d"' EXIT
kext_build "$d/k"
set -- "$d"/k/obj/*.o
[ -f "$1" ] || { echo "FAIL: no objects in $d/k/obj"; exit 1; }
# platform: llvm-nm -g lists external symbols; a private extern (hidden) one is not external once linked, and
#           llvm-nm -m marks it "private external", which is how the kext link will treat it
"$NM" -m "$@" | awk '/ external / && !/private external/ && !/undefined/ { print $NF }' | LC_ALL=C sort -u > "$d/got"
printf '%s\n' ___memcpy_chk ___strncpy_chk _buf_map_range _buf_unmap_range _kmod_info _ubc_upl_map_range \
  _vfs_get_notify_attributes _vnode_notify | LC_ALL=C sort > "$d/want"
diff "$d/want" "$d/got" > "$d/diff" || { echo "FAIL: the kext's exports differ (< missing, > extra):"; grep '^[<>]' "$d/diff"; exit 1; }
