#!/bin/sh
# platform: host-agnostic -- links AppKit consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C methods" -- -[NSControl usesSingleLineMode] and its setter (10.10) are its cell's, behind
#       the AppKit root ___recaulk_objc_activate; unrooted, NSControl lacks them.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
A="$T/lib/librecaulk-objc.a"
if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -c tests/c/objc_control_single_line.m -o "$(tbin single-line.o)"
  "$CC" $FLAGS "$(tbin single-line.o)" "$A" -framework AppKit -framework Carbon -o "$(tbin unrooted)"
  "$CC" $FLAGS "$(tbin single-line.o)" "$A" -Wl,-u,___recaulk_objc_activate -framework AppKit -framework Carbon \
    -o "$(tbin rooted)"
  check_loads "$(tbin unrooted)" "$(tbin rooted)"
fi
runtime_half
"$(tbin unrooted)" unrooted
"$(tbin rooted)" rooted
echo "objc-control-single-line OK"
