#!/bin/sh
# platform: host-agnostic -- builds the staged static archive and dylib's x86_64 programs; runs them on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  work="$(mktemp -d "${TMPDIR:-/tmp}/strtonum.XXXXXX")"
  trap 'rm -rf "$work"' EXIT
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" \
    tests/c/strtonum_contract.c "$T/lib/librecaulk.a" -o "$(tbin static)"
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" \
    tests/c/strtonum_contract.c -L"$T/lib" -lRecaulkSystem -o "$(tbin dylib)"
  check_loads "$(tbin static)" "$(tbin dylib)"
  printf '#include <stdlib.h>\nlong long (*parse)(const char *, long long, long long, const char **) = strtonum;\n' |
    "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" -x c -c -o "$work/header.o" -
fi
runtime_half
"$(tbin static)"
DYLD_LIBRARY_PATH="$T/lib" "$(tbin dylib)"
