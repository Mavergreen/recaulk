#ifndef RECAULK_APPKIT_NSPASTEBOARD_H
#define RECAULK_APPKIT_NSPASTEBOARD_H

#include_next <AppKit/NSPasteboard.h>

/* spec: README.md, "AppKit data"; librecaulk.a defines it, equal to AppKit's 10.13 constant by
   isEqual:, not by pointer */
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101300
APPKIT_EXTERN NSString *const NSPasteboardTypeFileURL;
#endif

#endif
