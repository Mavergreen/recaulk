#!/bin/sh
# platform: macOS-only -- builds the staged static archive and dylib's x86_64 programs; runs them on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
cc() { /usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" "$@"; }
if compiling; then
  cc tests/c/posix_spawn_chdir.c "$T/lib/librecaulk.a" -o "$(tbin static)"
  # spec: README.md "Child processes" -- librecaulk.a at the very end of the link, after libSystem,
  #       as a toolchain that appends it may place it, must still honour the chdir actions.
  cc tests/c/posix_spawn_chdir.c -lSystem "$T/lib/librecaulk.a" -o "$(tbin tail)"
  cc tests/c/posix_spawn_chdir.c -L"$T/lib" -lRecaulkSystem -o "$(tbin dylib)"
  check_loads "$(tbin static)" "$(tbin tail)" "$(tbin dylib)"
fi
runtime_half
"$(tbin static)"
"$(tbin tail)"
DYLD_LIBRARY_PATH="$T/lib" "$(tbin dylib)"
