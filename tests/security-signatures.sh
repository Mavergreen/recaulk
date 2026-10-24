#!/bin/sh
# platform: macOS-only -- links and runs an x86_64 program against librecaulk.a and Security.framework
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
D="$(mktemp -d "${TMPDIR:-/tmp}/security-signatures.XXXXXX")"
trap 'rm -rf "$D"' EXIT

/usr/bin/clang $FLAGS -arch x86_64 -Wall -Wno-deprecated-declarations -isystem "$T/include/recaulk" \
  -o "$D/security_signatures" tests/c/security_signatures.c "$T/lib/librecaulk.a" \
  -framework CoreFoundation -framework Security -framework CoreServices -lobjc \
  || { echo "FAIL: a program calling SecKeyCreateSignature does not link plainly with librecaulk.a"; exit 1; }
out="$("$D/security_signatures" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
case "$out" in
  *"security_signatures: all passed"*) [ "$rc" = 0 ] && { echo "security-signatures OK"; exit 0; } ;;
esac
echo "FAIL: SecKeyCreateSignature does not sign as Apple's API does (spec, back-fills match the real API; README.md, Security), exit $rc"
exit 1
