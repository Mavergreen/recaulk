#!/bin/sh
# platform: host-agnostic -- links AppKit consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C methods" -- the class-method groups: +[NSTimer scheduledTimerWithTimeInterval:repeats:block:]
#       and +timerWithTimeInterval:repeats:block: behind ___recaulk_objc_activate_timer, +[NSColor labelColor] and
#       +linkColor behind ___recaulk_objc_activate_color, and +[NSGraphicsContext graphicsContextWithCGContext:flipped:]
#       behind ___recaulk_objc_activate_graphics_context. Unrooted, 10.9 lacks them all; a group finding any member
#       already there adds none of its members.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
A="$T/lib/librecaulk-objc.a"
ROOTS="-Wl,-u,___recaulk_objc_activate_timer -Wl,-u,___recaulk_objc_activate_color -Wl,-u,___recaulk_objc_activate_graphics_context"
if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  "$CC" $FLAGS -fno-objc-arc -fblocks -Wall -Werror -c tests/c/objc_class_providers.m -o "$(tbin providers.o)"
  "$CC" $FLAGS -fno-objc-arc -fblocks -Wall -Werror -DRECAULK_OWN_LABEL_COLOR -c tests/c/objc_class_providers.m \
    -o "$(tbin own.o)"
  "$CC" $FLAGS "$(tbin providers.o)" "$A" -framework AppKit -o "$(tbin unrooted)"
  "$CC" $FLAGS "$(tbin providers.o)" "$A" $ROOTS -framework AppKit -o "$(tbin rooted)"
  "$CC" $FLAGS "$(tbin own.o)" "$A" $ROOTS -framework AppKit -o "$(tbin own-label-color)"
  check_loads "$(tbin unrooted)" "$(tbin rooted)" "$(tbin own-label-color)"
fi
runtime_half
"$(tbin unrooted)" unrooted
"$(tbin rooted)" rooted
"$(tbin own-label-color)" own-label-color
echo "objc-class-providers OK"
