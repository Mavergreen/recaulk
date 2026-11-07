#!/bin/sh
# platform: host-agnostic -- links an x86_64 program against librecaulk.a and Security.framework; runs it on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Wno-deprecated-declarations -isystem "$T/include/recaulk" \
    -o "$(tbin security_signatures)" tests/c/security_signatures.c "$T/lib/librecaulk.a" \
    -framework CoreFoundation -framework Security -framework CoreServices -lobjc \
    || { echo "FAIL: a program calling SecKeyCreateSignature does not link plainly with librecaulk.a"; exit 1; }
  check_loads "$(tbin security_signatures)"
fi
runtime_half
out="$("$(tbin security_signatures)" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
case "$out" in
  *"security_signatures: all passed"*) [ "$rc" = 0 ] && { echo "security-signatures OK"; exit 0; } ;;
esac
echo "FAIL: SecKeyCreateSignature does not sign as Apple's API does (spec, back-fills match the real API; README.md, Security), exit $rc"
exit 1
