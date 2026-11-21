#!/bin/sh
# platform: host-agnostic -- links AppKit consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C methods" -- -[NSWorkspace accessibilityDisplayShouldReduceMotion] answers NO, behind
#       the AppKit root ___recaulk_objc_activate; unrooted, NSWorkspace lacks it.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
A="$T/lib/librecaulk-objc.a"
if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -c tests/c/objc_workspace_reduce_motion.m -o "$(tbin reduce-motion.o)"
  "$CC" $FLAGS "$(tbin reduce-motion.o)" "$A" -framework AppKit -framework Carbon -o "$(tbin unrooted)"
  "$CC" $FLAGS "$(tbin reduce-motion.o)" "$A" -Wl,-u,___recaulk_objc_activate -framework AppKit -framework Carbon \
    -o "$(tbin rooted)"
  check_loads "$(tbin unrooted)" "$(tbin rooted)"
fi
runtime_half
"$(tbin unrooted)" unrooted
"$(tbin rooted)" rooted
echo "objc-workspace-reduce-motion OK"
