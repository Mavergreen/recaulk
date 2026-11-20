#!/bin/sh
# platform: host-agnostic -- links against the 10.9 SDK
# spec: README.md "How to use" -- share/recaulk/unexported-symbols.txt names every global librecaulk.a defines,
#       so a dylib that links the archive with -Wl,-unexported_symbols_list exports none of Recaulk's back-fills
#       (the macFUSE spike's libfuse dylibs exported _clock_gettime and _aligned_alloc without it)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
d="$(mktemp -d "${TMPDIR:-/tmp}/unexported.XXXXXX")"
trap 'rm -rf "$d"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
list="$T/share/recaulk/unexported-symbols.txt"
[ -f "$list" ] || { echo "FAIL: $list is not staged"; exit 1; }
"$NM" -gU "$T/lib/librecaulk.a" | awk 'NF >= 3 { print $NF }' | LC_ALL=C sort -u > "$d/globals"
LC_ALL=C sort -u "$list" | cmp -s - "$d/globals" || bad "the list is not exactly librecaulk.a's globals: $(LC_ALL=C sort -u "$list" | diff - "$d/globals" | grep '^[<>]' | head -5 | tr '\n' ' ')"
cat > "$d/lib.c" <<'C'
#include <stdlib.h>
#include <time.h>
int lib_now(void) { struct timespec ts; return clock_gettime(CLOCK_MONOTONIC, &ts); }
void *lib_alloc(void) { return aligned_alloc(64, 64); }
C
dylib() { "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" -dynamiclib "$d/lib.c" "$T/lib/librecaulk.a" "$@"; }
dylib -o "$d/without.dylib"
for s in _clock_gettime _aligned_alloc; do
  "$NM" -gU "$d/without.dylib" | grep -q " $s\$" || bad "control: a dylib linked without the list does not export $s, so this test proves nothing"
done
dylib -Wl,-unexported_symbols_list,"$list" -o "$d/with.dylib"
"$NM" -gU "$d/with.dylib" | awk 'NF >= 3 { print $NF }' | LC_ALL=C sort -u > "$d/exported"
leaked="$(LC_ALL=C comm -12 "$d/exported" "$d/globals" | tr '\n' ' ')"
[ -z "$leaked" ] || bad "a dylib linked with the list still exports Recaulk's: $leaked"
grep -qx _lib_now "$d/exported" || bad "the list hid the dylib's own _lib_now"
exit $fail
