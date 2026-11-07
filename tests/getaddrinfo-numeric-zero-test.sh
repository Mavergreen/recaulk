#!/bin/sh
# platform: host-agnostic -- exercises the system resolver through Recaulk's header; runs on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -isystem "$T/include/recaulk" \
    tests/c/getaddrinfo_numeric_zero.c -o "$(tbin test)"
  check_loads "$(tbin test)"
fi
runtime_half
"$(tbin test)"
