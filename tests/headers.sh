#!/bin/sh
# platform: macOS-only -- compiles against the 10.9 SDK
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }

d="$(mktemp -d "${TMPDIR:-/tmp}/headers.XXXXXX")"
trap 'rm -rf "$d"' EXIT
inc="$T/include/recaulk"
layer=_recaulk_macports
{
  echo '#include <MacportsLegacySupport.h>'
  echo '#include <os/lock.h>'
  echo '#include <time.h>'
  (cd src/include && find . -type f | sed 's|^\./||' | LC_ALL=C sort) | sed 's|.*|#include <&>|'
  echo 'int main(void){return 0;}'
} > "$d/all.c"
[ -n "$(find src/include -type f 2>/dev/null)" ] || bad "src/include holds no headers"
/usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -I"$inc" -c "$d/all.c" -o "$d/all.o" || bad "the headers do not compile together"

mp="$W/mp-headers/include/LegacySupport"
[ -d "$mp" ] || bad "no installed MacPorts header tree at $mp to compare against"
[ ! -e "src/include/$layer" ] || bad "src/include/$layer is the staged MacPorts layer's name; Recaulk's own headers cannot live there"
for h in $(cd "$mp" && find . -type f | sed 's|^\./||'); do
  if [ -f "src/include/$h" ]; then
    cmp -s "$mp/$h" "$inc/$layer/$h" || bad "MacPorts' $h is not staged unmodified at include/recaulk/$layer/$h"
    first="$(grep -m 1 '^[[:space:]]*#' "src/include/$h" | tr -s ' \t' ' ' | sed 's/^ //; s/# /#/')"
    [ "$first" = "#include <$layer/$h>" ] || bad "src/include/$h wraps MacPorts' header, so its first directive must be #include <$layer/$h>, not: $first"
  else
    cmp -s "$mp/$h" "$inc/$h" || bad "MacPorts' $h is not staged unmodified at include/recaulk/$h"
    [ ! -e "$inc/$layer/$h" ] || bad "include/recaulk/$layer/$h is staged, but Recaulk does not wrap $h"
  fi
done
for h in $(cd "$inc/$layer" 2>/dev/null && find . -type f | sed 's|^\./||'); do
  [ -f "$mp/$h" ] || bad "include/recaulk/$layer/$h is not one of MacPorts' headers"
done
for h in $(cd src/include && find . -type f | sed 's|^\./||'); do
  cmp -s "src/include/$h" "$inc/$h" || bad "src/include/$h is not staged at include/recaulk/$h"
done

decls() {
  _dc_src="$1"; shift
  /usr/bin/clang $FLAGS -arch x86_64 -isystem "$inc" -E "$@" "$_dc_src" 2>"$d/E.err" | grep -c '\baligned_alloc[[:space:]]*(' || true
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
    /usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$inc" $std -c "$d/$f.c" -o "$d/$f.o" \
      || bad "<stdlib.h> through include/recaulk declares no usable aligned_alloc ($f.c ${std:-default})"
    n="$(decls "$d/$f.c" $std)"
    [ "$n" = 1 ] || bad "aligned_alloc is declared $n times, not once ($f.c ${std:-default})"
  done
done
. tests/helpers/cxx.sh
for f in cstd stdc; do
  /usr/bin/clang++ $FLAGS -arch x86_64 -Wall -Werror $CXX_STD -isystem "$inc" -c "$d/$f.cpp" -o "$d/$f.o" \
    || bad "C++ through include/recaulk sees no ::aligned_alloc ($f.cpp)"
  n="$(decls "$d/$f.cpp" $CXX_STD)"
  [ "$n" = 1 ] || bad "aligned_alloc is declared $n times in C++, not once ($f.cpp)"
done

/usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$inc" -c src/backfills/aligned_alloc.c -o "$d/aligned_alloc.o" \
  || bad "src/backfills/aligned_alloc.c does not agree with the staged declaration"

probe strict c '#include <stdlib.h>'
n="$(decls "$d/strict.c" -std=c99 -D_POSIX_C_SOURCE=200809L)"
[ "$n" = 0 ] || bad "strict C99 POSIX sees $n aligned_alloc declarations; the SDK that declares it hides it there"

SDK113="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)"
probe sdk113 c '#include <stdlib.h>'
n="$(/usr/bin/clang -isysroot "$SDK113" -mmacosx-version-min=10.15 -arch x86_64 -isystem "$inc" -E "$d/sdk113.c" | grep -c '\baligned_alloc[[:space:]]*(' || true)"
[ "$n" = 1 ] || bad "with the 11.3 SDK, which declares aligned_alloc itself, it is declared $n times, not once"

printf '#include <stdlib.h>\n.text\n' > "$d/asm.S"
/usr/bin/clang $FLAGS -arch x86_64 -isystem "$inc" -E -x assembler-with-cpp "$d/asm.S" > "$d/asm.i" \
  || bad "assembly cannot preprocess <stdlib.h> through include/recaulk"
! grep -q aligned_alloc "$d/asm.i" || bad "assembly preprocessed through include/recaulk sees an aligned_alloc declaration"
printf '.text\n.globl _recaulk_probe\n_recaulk_probe:\n  ret\n' > "$d/plain.s"
/usr/bin/clang $FLAGS -arch x86_64 -isystem "$inc" -c "$d/plain.s" -o "$d/plain.o" \
  || bad "a plain .s does not assemble with include/recaulk on the path"

[ "$fail" = 0 ] && echo "headers OK"
exit $fail
