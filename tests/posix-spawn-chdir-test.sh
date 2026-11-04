#!/bin/sh
# platform: macOS-only -- tests the staged static archive and dylib on x86_64
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo 'SKIP: this host cannot run x86_64 programs'; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/spawn-chdir.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cc() { /usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" "$@"; }
cc tests/c/posix_spawn_chdir.c "$T/lib/librecaulk.a" -o "$work/static"
"$work/static"
# spec: README.md "Child processes" -- librecaulk.a at the very end of the link, after libSystem,
#       as a toolchain that appends it may place it, must still honour the chdir actions.
cc tests/c/posix_spawn_chdir.c -lSystem "$T/lib/librecaulk.a" -o "$work/tail"
"$work/tail"
cc tests/c/posix_spawn_chdir.c -L"$T/lib" -lRecaulkSystem -o "$work/dylib"
DYLD_LIBRARY_PATH="$T/lib" "$work/dylib"
