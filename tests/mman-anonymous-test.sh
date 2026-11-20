#!/bin/sh
# platform: host-agnostic -- compiles against the 10.9 SDK
# spec: README.md "Declarations" -- <sys/mman.h> names MAP_ANONYMOUS exactly where 10.9's own header names
#       MAP_ANON (!_POSIX_C_SOURCE || _DARWIN_C_SOURCE), so a strict-POSIX probe such as `#ifdef MAP_ANONYMOUS`
#       takes the branch that compiles
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
d="$(mktemp -d "${TMPDIR:-/tmp}/mman.XXXXXX")"
trap 'rm -rf "$d"' EXIT
fail=0
cat > "$d/probe.c" <<'C'
#include <sys/mman.h>
#include <stddef.h>
void *f(void) {
#ifdef MAP_ANONYMOUS
  return mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
#else
  return NULL;
#endif
}
int anonymous_visible(void) {
#ifdef MAP_ANONYMOUS
  return 1;
#else
  return 0;
#endif
}
C
cc() { "$CC" $FLAGS -arch x86_64 -Wall -Werror -I"$T/include/recaulk" "$@" -c "$d/probe.c" -o "$d/probe.o"; }
vis() { "$CC" $FLAGS -arch x86_64 -I"$T/include/recaulk" "$@" -E -dM "$d/probe.c" | grep -c '^#define MAP_ANONYMOUS ' || true; }
cc -D_POSIX_C_SOURCE=200809L || { echo "FAIL: under _POSIX_C_SOURCE=200809L, a probe guarded by #ifdef MAP_ANONYMOUS does not compile"; fail=1; }
[ "$(vis -D_POSIX_C_SOURCE=200809L)" = 0 ] || { echo "FAIL: MAP_ANONYMOUS is defined under _POSIX_C_SOURCE, where 10.9 hides MAP_ANON"; fail=1; }
[ "$(vis -D_POSIX_C_SOURCE=200809L -D_DARWIN_C_SOURCE)" = 1 ] || { echo "FAIL: MAP_ANONYMOUS is missing under _POSIX_C_SOURCE with _DARWIN_C_SOURCE"; fail=1; }
[ "$(vis)" = 1 ] || { echo "FAIL: MAP_ANONYMOUS is missing by default"; fail=1; }
cc || { echo "FAIL: the probe does not compile by default"; fail=1; }
exit $fail
