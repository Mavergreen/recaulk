#include <CoreGraphics/CGBase.h>

/* Foundation constant (added 10.10): insets of zero. NSEdgeInsets is AppKit's on 10.9 and Foundation's on 10.10+,
   with the same four CGFloat fields. Not Foundation's object on 10.10+, which no caller can tell by value. */
const struct { CGFloat top, left, bottom, right; } NSEdgeInsetsZero = { 0, 0, 0, 0 };
