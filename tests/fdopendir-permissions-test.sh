#!/bin/sh
# platform: host-agnostic -- builds both Darwin inode ABIs through the staged Recaulk wrapper; runs them on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  for abi in default ino32; do
    define=
    [ "$abi" != ino32 ] || define=-D_DARWIN_NO_64_BIT_INODE=1
    "$CC" $FLAGS -arch x86_64 $define -isystem "$T/include/recaulk" \
      tests/c/fdopendir_permissions.c "$T/lib/librecaulk.a" -o "$(tbin "test-$abi")"
    check_loads "$(tbin "test-$abi")"
  done
fi
runtime_half
[ "$(id -u)" != 0 ] || { echo 'SKIP: root bypasses directory permissions'; exit 77; }
for abi in default ino32; do
  "$(tbin "test-$abi")"
done
