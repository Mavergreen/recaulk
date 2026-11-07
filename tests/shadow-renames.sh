#!/bin/sh
# platform: host-agnostic -- compiles and links x86_64 programs against the 10.9 SDK; reads them with nm
# spec: README.md "Fixes to functions 10.9 has" -- a program built from source against Recaulk's headers calls
#       Recaulk's fix of every C function build/image-local-shadows.txt lists, whatever its link order: a -lm,
#       -ldl, -lpthread or -lc ahead of librecaulk.a names libSystem itself, whose broken copy would bind first.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
d="$(mktemp -d "${TMPDIR:-/tmp}/shadow-renames.XXXXXX")"
trap 'rm -rf "$d"' EXIT

# The C functions the list fixes: its symbols, less C++'s and less the $-variants of one function.
grep -v '^#' build/image-local-shadows.txt | awk 'NF { print $2 }' | grep -v '^__Z' | sed 's/^_//; s/\$.*//' \
  | LC_ALL=C sort -u > "$d/fixed"
[ -s "$d/fixed" ] || bad "build/image-local-shadows.txt lists no C function"
header_of() {
  case "$1" in
    pselect) echo sys/select.h ;;
    posix_spawn*) echo spawn.h ;;
    fma|fmal|truncl) echo math.h ;;
    *) return 1 ;;
  esac
}
{
  for f in $(cat "$d/fixed"); do
    h="$(header_of "$f")" || { bad "no header known for $f, which build/image-local-shadows.txt fixes"; continue; }
    echo "#include <$h>"
  done | LC_ALL=C sort -u
  echo 'int main(void) {'
  for f in $(cat "$d/fixed"); do echo "  { volatile void *p = (void *)&$f; (void)p; }"; done
  echo '  return 0;'
  echo '}'
} > "$d/calls.c"
for libs in "-lm -ldl -lpthread -lc" ""; do
  # shellcheck disable=SC2086 # FLAGS and libs are word lists
  "$CC" $FLAGS -arch x86_64 -isystem "$T/include/recaulk" "$d/calls.c" $libs "$T/lib/librecaulk.a" -o "$d/calls" \
    || { bad "a program taking each fixed function's address does not build (libraries first: ${libs:-none})"; continue; }
  "$NM" -u "$d/calls" > "$d/imports" || { bad "$NM cannot read the program"; continue; }
  for f in $(cat "$d/fixed"); do
    if grep -Eq "^_$f(\\\$|\$)" "$d/imports"; then
      bad "a program that names ${libs:-no library} before librecaulk.a imports 10.9's $f: $(grep -E "^_$f(\\\$|\$)" "$d/imports" | tr '\n' ' ')"
    fi
  done
done
# The same program linked against libRecaulkSystem.dylib, which exports what Recaulk's headers name.
# shellcheck disable=SC2086 # FLAGS is a word list
"$CC" $FLAGS -arch x86_64 -isystem "$T/include/recaulk" "$d/calls.c" -L"$T/lib" -lRecaulkSystem -o "$d/calls-dylib" \
  || bad "a program taking each fixed function's address does not link against libRecaulkSystem.dylib"
[ "$fail" = 0 ] && echo "PASS: a program built against Recaulk's headers calls Recaulk's fix of each of $(wc -l < "$d/fixed" | tr -d ' ') functions, whatever its link order"
exit "$fail"
