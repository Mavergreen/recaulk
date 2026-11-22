#!/bin/sh
# platform: host-agnostic -- links an x86_64 program against librecaulk.a with clang22; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "AppKit data" -- librecaulk.a defines the 10.10 and 10.14 appearance names, each its own name as a
#       string, and NSEdgeInsetsZero (10.10), needing CoreFoundation only, never AppKit.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Werror tests/c/appkit_data.c "$T/lib/librecaulk.a" -framework CoreFoundation \
    -o "$(tbin program)"
  if "$OTOOL" -L "$(tbin program)" | grep -q '/AppKit\.framework/'; then
    echo "FAIL: a program using librecaulk.a's AppKit data loads AppKit"; exit 1
  fi
  check_loads "$(tbin program)"
fi
runtime_half
"$(tbin program)"
