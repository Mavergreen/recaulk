#!/bin/sh
# platform: macOS-only -- links x86_64 Mach-O against librecaulk.a and reads its imports with nm
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/security-weak.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

cat > "$D/uses.c" <<'C'
#include <Security/Security.h>
int main(void) {
  return SecTrustEvaluateWithError(NULL, NULL) || SecTrustCopyCertificateChain(NULL) ||
         SecKeyCreateSignature(NULL, kSecKeyAlgorithmECDSASignatureDigestX962SHA256, NULL, NULL);
}
C
/usr/bin/clang $FLAGS -arch x86_64 -isystem "$T/include/recaulk" -o "$D/uses" "$D/uses.c" "$T/lib/librecaulk.a" \
  -framework CoreFoundation -framework Security -framework CoreServices -lobjc \
  || { echo "FAIL: a program calling the Security back-fills does not link plainly with librecaulk.a"; exit 1; }
"${NM:-nm}" -m "$D/uses" > "$D/imports"
for sym in _SecKeychainErrFromOSStatus _SecKeyRawSign; do
  line="$(grep " external $sym " "$D/imports" || true)"
  case "$line" in
    "") bad "$sym is not imported at all; the back-fill no longer reaches it, so this test no longer guards anything" ;;
    *"weak external"*) echo "$sym: $line" ;;
    *) bad "$sym is a strong import ($line): it is not in any SDK header, and a macOS that drops it would refuse to launch every program linking these back-fills, though there the system's own functions run (spec, README.md, Security)" ;;
  esac
done

[ "$fail" = 0 ] && echo "security-weak-imports OK"
exit $fail
