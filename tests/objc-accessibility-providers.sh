#!/bin/sh
# platform: host-agnostic -- links AppKit consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C methods" -- the NSAccessibility groups: 10.10's label, role, children and selected-text-
#       range setters and getters and -accessibilityFrame, on NSView behind ___recaulk_objc_activate_view_accessibility
#       and on NSCell behind ___recaulk_objc_activate_cell_accessibility. Unrooted, 10.9 lacks them all; a group finding
#       any member already there adds none of its members, and the other group is independent of it.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
A="$T/lib/librecaulk-objc.a"
ROOTS="-Wl,-u,___recaulk_objc_activate_view_accessibility -Wl,-u,___recaulk_objc_activate_cell_accessibility"
if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -c tests/c/objc_accessibility_providers.m -o "$(tbin ax.o)"
  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -DRECAULK_OWN_VIEW_LABEL -c tests/c/objc_accessibility_providers.m \
    -o "$(tbin ax-own.o)"
  "$CC" $FLAGS "$(tbin ax.o)" "$A" -framework AppKit -o "$(tbin ax-unrooted)"
  "$CC" $FLAGS "$(tbin ax.o)" "$A" $ROOTS -framework AppKit -o "$(tbin ax-rooted)"
  "$CC" $FLAGS "$(tbin ax-own.o)" "$A" $ROOTS -framework AppKit -o "$(tbin ax-own-view-label)"
  check_loads "$(tbin ax-unrooted)" "$(tbin ax-rooted)" "$(tbin ax-own-view-label)"
fi
runtime_half
"$(tbin ax-unrooted)" unrooted
"$(tbin ax-rooted)" rooted
"$(tbin ax-own-view-label)" own-view-label
echo "objc-accessibility-providers OK"
