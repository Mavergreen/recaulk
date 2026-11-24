#!/bin/sh
# platform: host-agnostic -- builds an x86_64 program from src/kfix/engine.c; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "The kernel-fixes kext" -- a fix writes only over the bytes it expects, stands down over its own
#       replacement, refuses anything else, and the recaulk_kfix boot-arg turns all fixes or named ones off; a hook
#       finds the one call after its expected bytes, stores its displacement within a cache line, and reaches a
#       trampoline in padding after a ret. On 10.9.5 13F1911, the pinned sites are checked in /mach_kernel, read only.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror -Isrc/kext tests/c/kfix_engine.c src/kfix/engine.c src/kext/core.c \
    src/kfix/kqueue_scan_restart.c src/kfix/wait_result_prepost.c -o "$(tbin engine)"
  check_loads "$(tbin engine)"
fi
runtime_half
"$(tbin engine)" /mach_kernel
