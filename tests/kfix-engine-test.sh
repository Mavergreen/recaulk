#!/bin/sh
# platform: host-agnostic -- builds an x86_64 program from src/kfix/engine.c; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "The kernel-fixes kext" -- a fix writes only over the bytes it expects, stands down over its own
#       replacement, refuses anything else, and the recaulk_kfix boot-arg turns all fixes or named ones off
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror tests/c/kfix_engine.c src/kfix/engine.c -o "$(tbin engine)"
  check_loads "$(tbin engine)"
fi
runtime_half
"$(tbin engine)"
