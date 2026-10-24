#!/bin/sh
# platform: macOS-only -- both Darwin inode ABIs through the staged Recaulk wrapper.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo 'SKIP: this host cannot run x86_64 programs'; exit 77; }
[ "$(id -u)" != 0 ] || { echo 'SKIP: root bypasses directory permissions'; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/fdopendir-permissions.XXXXXX")"
trap 'rm -rf "$work"' EXIT
for abi in default ino32; do
  define=
  [ "$abi" != ino32 ] || define=-D_DARWIN_NO_64_BIT_INODE=1
  /usr/bin/clang $FLAGS -arch x86_64 $define -isystem "$T/include/recaulk" \
    tests/c/fdopendir_permissions.c "$T/lib/librecaulk.a" -o "$work/test"
  "$work/test"
done
