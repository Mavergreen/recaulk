#!/bin/sh
# platform: host-agnostic -- links AppKit consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C methods" -- the accessibility bridge: an app calls recaulk_accessibility_bridge once per
#       class that implements only 10.10's NSAccessibility getters, and 10.9's attribute API then answers from them.
#       Uncalled it adds nothing; with Recaulk's NSView and NSCell setter groups linked too, neither loops into the other.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
A="$T/lib/librecaulk-objc.a"
SETTERS="-Wl,-u,___recaulk_objc_activate_view_accessibility -Wl,-u,___recaulk_objc_activate_cell_accessibility"
if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  [ -f "$T/include/recaulk/recaulk/accessibility.h" ] || { echo "FAIL: the stage has no include/recaulk/recaulk/accessibility.h"; exit 1; }
  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -isystem "$T/include/recaulk" -c tests/c/objc_accessibility_bridge.m \
    -o "$(tbin bridge.o)"
  "$CC" $FLAGS "$(tbin bridge.o)" "$A" -framework AppKit -o "$(tbin bridge)"
  "$CC" $FLAGS "$(tbin bridge.o)" "$A" $SETTERS -framework AppKit -o "$(tbin bridge-with-setters)"
  check_loads "$(tbin bridge)" "$(tbin bridge-with-setters)"
fi
runtime_half
"$(tbin bridge)" unbridged
"$(tbin bridge)" bridged
"$(tbin bridge-with-setters)" bridged
"$(tbin bridge-with-setters)" bridged-with-setters
echo "objc-accessibility-bridge OK"
