#!/bin/sh
# platform: macOS-only -- links and runs an x86_64 program against librecaulk.a and Security.framework
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
D="$(mktemp -d "${TMPDIR:-/tmp}/security-trust.XXXXXX")"
trap 'rm -rf "$D"' EXIT

/usr/bin/clang $FLAGS -arch x86_64 -Wall -Wno-deprecated-declarations -isystem "$T/include/recaulk" \
  -o "$D/security_trust" tests/c/security_trust.c "$T/lib/librecaulk.a" \
  -framework CoreFoundation -framework Security -framework CoreServices -lobjc \
  || { echo "FAIL: a program calling SecTrustEvaluateWithError does not link plainly with librecaulk.a"; exit 1; }
out="$("$D/security_trust" tests/fixtures 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
case "$out" in
  *"security_trust: all passed"*) [ "$rc" = 0 ] && { echo "security-trust OK"; exit 0; } ;;
esac
echo "FAIL: the trust back-fills do not answer as Apple's API does (spec, back-fills match the real API; README.md, Security), exit $rc"
exit 1
