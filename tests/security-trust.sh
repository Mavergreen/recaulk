#!/bin/sh
# platform: macOS-only -- links an x86_64 program against librecaulk.a and Security.framework; runs it on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  /usr/bin/clang $FLAGS -arch x86_64 -Wall -Wno-deprecated-declarations -isystem "$T/include/recaulk" \
    -o "$(tbin security_trust)" tests/c/security_trust.c "$T/lib/librecaulk.a" \
    -framework CoreFoundation -framework Security -framework CoreServices -lobjc \
    || { echo "FAIL: a program calling SecTrustEvaluateWithError does not link plainly with librecaulk.a"; exit 1; }
  check_loads "$(tbin security_trust)"
fi
runtime_half
out="$("$(tbin security_trust)" tests/fixtures 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
case "$out" in
  *"security_trust: all passed"*) [ "$rc" = 0 ] && { echo "security-trust OK"; exit 0; } ;;
esac
echo "FAIL: the trust back-fills do not answer as Apple's API does (spec, back-fills match the real API; README.md, Security), exit $rc"
exit 1
