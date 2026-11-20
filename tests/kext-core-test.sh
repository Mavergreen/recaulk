#!/bin/sh
# platform: host-agnostic -- builds an x86_64 program from src/kext/core.c; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "The kernel back-fill kext" -- the version gate, and the kernel-file reader against malformed
#       files (short or overlong load commands, tables past the file, names past the string table, a fat
#       slice past the file, a live header walk that would leave sizeofcmds), then against 10.9's /mach_kernel
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror tests/c/kext_core.c src/kext/core.c -o "$(tbin core)"
  check_loads "$(tbin core)"
fi
runtime_half
"$(tbin core)" /mach_kernel
