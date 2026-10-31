#!/bin/sh
# platform: macOS-only -- tests the staged static archive and dylib on x86_64
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo 'SKIP: this host cannot run x86_64 programs'; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/strtonum.XXXXXX")"
trap 'rm -rf "$work"' EXIT
/usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" \
  tests/c/strtonum_contract.c "$T/lib/librecaulk.a" -o "$work/static"
"$work/static"
/usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" \
  tests/c/strtonum_contract.c -L"$T/lib" -lRecaulkSystem -o "$work/dylib"
DYLD_LIBRARY_PATH="$T/lib" "$work/dylib"
# Catch a missing public declaration as well as a missing runtime export.
printf '#include <stdlib.h>\nlong long (*parse)(const char *, long long, long long, const char **) = strtonum;\n' |
  /usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" -x c -c -o "$work/header.o" -
