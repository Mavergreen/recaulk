#ifndef RECAULK_APPKIT_NSLAYOUTCONSTRAINT_H
#define RECAULK_APPKIT_NSLAYOUTCONSTRAINT_H

#include_next <AppKit/NSLayoutConstraint.h>

/* spec: README.md, "AppKit data"; librecaulk.a defines it. The 10.10 SDK moved NSEdgeInsets to Foundation's
   NSGeometry.h and declared it there. */
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101000
APPKIT_EXTERN const NSEdgeInsets NSEdgeInsetsZero;
#endif

#endif
