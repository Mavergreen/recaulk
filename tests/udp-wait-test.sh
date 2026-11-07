#!/bin/sh
# platform: macOS-only -- combines native kqueue with UDP packet readiness; runs on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  /usr/bin/clang $FLAGS -arch x86_64 -Wall -Wextra -Werror \
    -isystem "$T/include/recaulk" tests/c/udp_wait.c "$T/lib/librecaulk.a" \
    -o "$(tbin test)"
  check_loads "$(tbin test)"
fi
runtime_half
"$(tbin test)"
