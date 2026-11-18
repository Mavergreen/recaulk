#ifndef RECAULK_COREGRAPHICS_CGCOLOR_H
#define RECAULK_COREGRAPHICS_CGCOLOR_H

#include_next <CoreGraphics/CGColor.h>

/* spec: README.md, "Core Graphics"; declared as Apple's CGColor.h gives it */
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101500
CG_EXTERN CGColorRef CGColorCreateSRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
#endif

#endif
