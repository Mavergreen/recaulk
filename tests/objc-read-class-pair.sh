#!/bin/sh
# platform: macOS-only -- builds and executes x86_64 Mach-O against 10.9's libobjc
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macos.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
ver="$(macos_version)"
if ! version_below "$ver" 10.10 || version_below "$ver" 10.9; then
  echo "SKIP: on $ver objc_readClassPair is the system's, and ours realizes only 10.9's class layout"
  exit 77
fi
D="$(mktemp -d "${TMPDIR:-/tmp}/readclasspair.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0

/usr/bin/clang $FLAGS -arch x86_64 -fno-objc-arc -o "$D/rcp" tests/c/objc_read_class_pair.m \
  tests/c/objc_read_class_pair_cxx.mm -lc++ \
  "$T/lib/librecaulk.a" -framework Foundation -framework CoreFoundation -framework Security \
  -framework CoreServices -lobjc \
  || { echo "FAIL: the objc_readClassPair test program does not link with librecaulk.a"; exit 1; }
for t in nsobject-methods custom-rr inherited-flags cxx-structors unrealized-parent meta-version; do
  rc=0
  "$D/rcp" "$t" || rc=$?
  [ "$rc" = 0 ] || { echo "FAIL: $t exited $rc"; fail=1; }
done

[ "$fail" = 0 ] && echo "objc-read-class-pair OK"
exit $fail
