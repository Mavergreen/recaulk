#!/bin/sh
# platform: host-agnostic -- links AppKit consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C methods" -- -[NSWindow titlebarAppearsTransparent] and its setter (10.10) read NO and ignore YES, behind
#       the AppKit root ___recaulk_objc_activate, as 10.9 draws no transparent titlebar; unrooted, NSWindow lacks them.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
A="$T/lib/librecaulk-objc.a"
if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -c tests/c/objc_window_titlebar.m -o "$(tbin titlebar.o)"
  "$CC" $FLAGS "$(tbin titlebar.o)" "$A" -framework AppKit -framework Carbon -o "$(tbin unrooted)"
  "$CC" $FLAGS "$(tbin titlebar.o)" "$A" -Wl,-u,___recaulk_objc_activate -framework AppKit -framework Carbon \
    -o "$(tbin rooted)"
  check_loads "$(tbin unrooted)" "$(tbin rooted)"
fi
runtime_half
"$(tbin unrooted)" unrooted
"$(tbin rooted)" rooted
echo "objc-window-titlebar OK"
