#!/bin/sh
# platform: macOS-only -- runs an x86_64 program built against the staged headers and librecaulk.a
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo 'SKIP: this host cannot run x86_64 programs'; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/aligned-alloc.XXXXXX")"
trap 'rm -rf "$work"' EXIT
/usr/bin/clang $FLAGS -arch x86_64 -std=c11 -Wall -Werror -isystem "$T/include/recaulk" \
  tests/c/aligned_alloc_contract.c "$T/lib/librecaulk.a" -o "$work/static"
"$work/static"
/usr/bin/clang $FLAGS -arch x86_64 -std=c11 -Wall -Werror -isystem "$T/include/recaulk" \
  tests/c/aligned_alloc_contract.c -L"$T/lib" -lRecaulkSystem -o "$work/dylib"
DYLD_LIBRARY_PATH="$T/lib" "$work/dylib"
