#!/bin/sh
# platform: macOS-only -- tests the staged static archive and dylib on x86_64
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo 'SKIP: this host cannot run x86_64 programs'; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/preadv.XXXXXX")"
trap 'rm -rf "$work"' EXIT
/usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" \
  tests/c/preadv_pwritev.c "$T/lib/librecaulk.a" -o "$work/static"
"$work/static"
/usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" \
  tests/c/preadv_pwritev.c -L"$T/lib" -lRecaulkSystem -o "$work/dylib"
DYLD_LIBRARY_PATH="$T/lib" "$work/dylib"
