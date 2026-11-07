#!/bin/sh
# platform: macOS-only -- builds an x86_64 program against the staged headers and librecaulk.a; runs it on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  /usr/bin/clang $FLAGS -arch x86_64 -std=c11 -Wall -Werror -isystem "$T/include/recaulk" \
    tests/c/aligned_alloc_contract.c "$T/lib/librecaulk.a" -o "$(tbin static)"
  /usr/bin/clang $FLAGS -arch x86_64 -std=c11 -Wall -Werror -isystem "$T/include/recaulk" \
    tests/c/aligned_alloc_contract.c -L"$T/lib" -lRecaulkSystem -o "$(tbin dylib)"
  check_loads "$(tbin static)" "$(tbin dylib)"
fi
runtime_half
"$(tbin static)"
DYLD_LIBRARY_PATH="$T/lib" "$(tbin dylib)"
