#!/bin/sh
# platform: host-agnostic -- compiles against the 10.9 SDK
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }

d="$(mktemp -d "${TMPDIR:-/tmp}/headers.XXXXXX")"
trap 'rm -rf "$d"' EXIT
inc="$T/include/recaulk"
layer=_recaulk_macports
cxx_only=cxxabi.h
{
  echo '#include <MacportsLegacySupport.h>'
  echo '#include <os/lock.h>'
  echo '#include <time.h>'
  (cd src/include && find . -type f | sed 's|^\./||' | LC_ALL=C sort) | grep -vx "$cxx_only" | sed 's|.*|#include <&>|'
  echo 'int main(void){return 0;}'
} > "$d/all.c"
[ -n "$(find src/include -type f 2>/dev/null)" ] || bad "src/include holds no headers"
"$CC" $FLAGS -arch x86_64 -Wall -Werror -I"$inc" -c "$d/all.c" -o "$d/all.o" || bad "the headers do not compile together"
# platform: the 10.9 SDK's cxxabi.h, which Recaulk's wraps, is C++ only
printf '#include <%s>\nint main() { return 0; }\n' $cxx_only > "$d/cxx.cpp"
"$CXX" $FLAGS -arch x86_64 -Wall -Werror -I"$inc" -c "$d/cxx.cpp" -o "$d/cxx.o" || bad "the C++-only headers ($cxx_only) do not compile"

mp="$W/mp-headers/include/LegacySupport"
[ -d "$mp" ] || bad "no installed MacPorts header tree at $mp to compare against"
beside() { _bs_d="$(dirname "$1")"; [ "$_bs_d" = . ] && _bs_d= || _bs_d="$_bs_d/"; printf '%s%s_%s\n' "$_bs_d" "$layer" "$(basename "$1")"; }
[ -z "$(cd src/include && find . -name "$layer*")" ] || bad "src/include holds a $layer name, the staged MacPorts layer's; Recaulk's own headers cannot use it"
# spec: README.md "How to use" -- a wrapped MacPorts header sits beside its wrapper, so its #include_next is in a
#       file directly in a search directory: zig translate-c's aro continues an #include_next only from there
[ ! -e "$inc/$layer" ] || bad "include/recaulk/$layer/ exists: a MacPorts header there does #include_next from a directory no search path names"
for h in $(cd "$mp" && find . -type f | sed 's|^\./||'); do
  if [ -f "src/include/$h" ]; then
    staged="$(beside "$h")"
    cmp -s "$mp/$h" "$inc/$staged" || bad "MacPorts' $h is not staged unmodified at include/recaulk/$staged"
    # platform: MacPorts' sys/clonefile.h, sys/fsgetpath.h and sys/random.h use what they never include, so the
    #           directives before it may only #include the headers MacPorts' copy needs.
    lead="$(grep '^[[:space:]]*#' "src/include/$h" | tr -s ' \t' ' ' | sed 's/^ //; s/# /#/' \
      | awk -v s="#include <$staged>" '$0 == s { found = 1; exit } { print } END { if (!found) print "(no " s ")" }')"
    other="$(printf '%s\n' "$lead" | grep -v '^#include <[^>]*>$' | head -n 1)"
    [ -z "$other" ] || bad "src/include/$h wraps MacPorts' header, so its first directive other than an #include of a header it needs must be #include <$staged>, not: $other"
  else
    cmp -s "$mp/$h" "$inc/$h" || bad "MacPorts' $h is not staged unmodified at include/recaulk/$h"
  fi
done
for f in $(cd "$inc" && find . -type f -name "$layer*" | sed 's|^\./||'); do
  fd="$(dirname "$f")"; [ "$fd" = . ] && h="${f#"$layer"_}" || h="$fd/$(basename "$f" | sed "s/^${layer}_//")"
  [ -f "src/include/$h" ] && [ -f "$mp/$h" ] || bad "include/recaulk/$f is staged, but it is not MacPorts' copy of a header Recaulk wraps"
done
for h in $(cd src/include && find . -type f | sed 's|^\./||'); do
  cmp -s "src/include/$h" "$inc/$h" || bad "src/include/$h is not staged at include/recaulk/$h"
done

decls() {
  _dc_src="$1"; shift
  "$CC" $FLAGS -arch x86_64 -isystem "$inc" -E "$@" "$_dc_src" 2>"$d/E.err" | grep -c '\baligned_alloc[[:space:]]*(' || true
}
probe() {
  _pr_name="$1"; _pr_lang="$2"; shift 2
  printf '%s\n' "$@" > "$d/$_pr_name.$_pr_lang"
}
use='void *(*recaulk_probe)(size_t, size_t) = aligned_alloc;'

probe std c '#include <stdlib.h>' "$use"
probe mpfirst c '#include <MacportsLegacySupport.h>' '#include <stdlib.h>' "$use"
probe malloc c '#include <malloc/malloc.h>' '#include <stdlib.h>' '#include <stdlib.h>' "$use"
probe wrappers c '#include <dirent.h>' '#include <netdb.h>' '#include <stdlib.h>' '#include <pthread/qos.h>' "$use"
probe cstd cpp '#include <cstdlib>' '#include <stdlib.h>' 'void *(*recaulk_probe)(std::size_t, std::size_t) = ::aligned_alloc;'
probe stdc cpp '#include <stdlib.h>' '#include <cstdlib>' 'void *(*recaulk_probe)(std::size_t, std::size_t) = ::aligned_alloc;'
for f in std mpfirst malloc wrappers; do
  for std in "" -std=c99 -std=c11 "-std=c11 -D_POSIX_C_SOURCE=200809L"; do
    "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$inc" $std -c "$d/$f.c" -o "$d/$f.o" \
      || bad "<stdlib.h> through include/recaulk declares no usable aligned_alloc ($f.c ${std:-default})"
    n="$(decls "$d/$f.c" $std)"
    [ "$n" = 1 ] || bad "aligned_alloc is declared $n times, not once ($f.c ${std:-default})"
  done
done
. tests/helpers/cxx.sh
for f in cstd stdc; do
  "$CXX" $FLAGS -arch x86_64 -Wall -Werror $CXX_STD -isystem "$inc" -c "$d/$f.cpp" -o "$d/$f.o" \
    || bad "C++ through include/recaulk sees no ::aligned_alloc ($f.cpp)"
  n="$(decls "$d/$f.cpp" $CXX_STD)"
  [ "$n" = 1 ] || bad "aligned_alloc is declared $n times in C++, not once ($f.cpp)"
done

"$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$inc" -c src/backfills/aligned_alloc.c -o "$d/aligned_alloc.o" \
  || bad "src/backfills/aligned_alloc.c does not agree with the staged declaration"

probe strict c '#include <stdlib.h>'
n="$(decls "$d/strict.c" -std=c99 -D_POSIX_C_SOURCE=200809L)"
[ "$n" = 0 ] || bad "strict C99 POSIX sees $n aligned_alloc declarations; the SDK that declares it hides it there"

SDK113="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)"
probe sdk113 c '#include <stdlib.h>'
n="$("$CC" --no-default-config --target=x86_64-apple-macos10.15 -isysroot "$SDK113" -mmacosx-version-min=10.15 -arch x86_64 -isystem "$inc" -E "$d/sdk113.c" | grep -c '\baligned_alloc[[:space:]]*(' || true)"
[ "$n" = 1 ] || bad "with the 11.3 SDK, which declares aligned_alloc itself, it is declared $n times, not once"

sec_use='CFDataRef (*recaulk_sign)(SecKeyRef, SecKeyAlgorithm, CFDataRef, CFErrorRef *) = SecKeyCreateSignature;
bool (*recaulk_eval)(SecTrustRef, CFErrorRef *) = SecTrustEvaluateWithError;
CFArrayRef (*recaulk_chain)(SecTrustRef) = SecTrustCopyCertificateChain;
const SecKeyAlgorithm *recaulk_alg = &kSecKeyAlgorithmECDSASignatureDigestX962SHA256;'
probe sec c '#include <Security/Security.h>' '#include <Security/SecKey.h>' '#include <Security/SecTrust.h>' "$sec_use"
probe seccpp cpp '#include <Security/Security.h>' "$sec_use"
for std in "" -std=c99 -std=c11; do
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$inc" $std -c "$d/sec.c" -o "$d/sec.o" \
    || bad "<Security/Security.h> through include/recaulk does not declare the signing and trust back-fills as Apple's SDK does (sec.c ${std:-default})"
done
"$CXX" $FLAGS -arch x86_64 -Wall -Werror $CXX_STD -isystem "$inc" -c "$d/seccpp.cpp" -o "$d/seccpp.o" \
  || bad "C++ through include/recaulk does not see the signing and trust back-fills"
for c in security.c security_signature.c; do
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -Wno-deprecated-declarations -isystem "$inc" -c "src/backfills/$c" -o "$d/$c.o" \
    || bad "src/backfills/$c does not agree with the staged Security declarations"
done
"$CC" --no-default-config --target=x86_64-apple-macos10.15 -isysroot "$SDK113" -mmacosx-version-min=10.15 -arch x86_64 -isystem "$inc" -E "$d/sec.c" > "$d/sec113.i" 2>"$d/sec113.err" \
  || bad "with the 11.3 SDK, <Security/Security.h> through include/recaulk does not preprocess: $(head -3 "$d/sec113.err")"
for decl in 'typedef CFStringRef SecKeyAlgorithm' 'SecKeyCreateSignature[[:space:]]*(' 'SecTrustEvaluateWithError[[:space:]]*(' 'SecTrustCopyCertificateChain[[:space:]]*('; do
  n="$(grep -c "$decl" "$d/sec113.i" || true)"
  [ "$n" = 1 ] || bad "with the 11.3 SDK, which declares the 10.12 and 10.14 Security API itself, '$decl' appears $n times, not once"
done

printf '#include <stdlib.h>\n.text\n' > "$d/asm.S"
"$CC" $FLAGS -arch x86_64 -isystem "$inc" -E -x assembler-with-cpp "$d/asm.S" > "$d/asm.i" \
  || bad "assembly cannot preprocess <stdlib.h> through include/recaulk"
! grep -q aligned_alloc "$d/asm.i" || bad "assembly preprocessed through include/recaulk sees an aligned_alloc declaration"
printf '.text\n.globl _recaulk_probe\n_recaulk_probe:\n  ret\n' > "$d/plain.s"
"$CC" $FLAGS -arch x86_64 -isystem "$inc" -c "$d/plain.s" -o "$d/plain.o" \
  || bad "a plain .s does not assemble with include/recaulk on the path"

[ "$fail" = 0 ] && echo "headers OK"
exit $fail
