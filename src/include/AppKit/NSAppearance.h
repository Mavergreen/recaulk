#ifndef RECAULK_APPKIT_NSAPPEARANCE_H
#define RECAULK_APPKIT_NSAPPEARANCE_H

#include_next <AppKit/NSAppearance.h>

/* spec: README.md, "AppKit data"; librecaulk.a defines them, equal to AppKit's constants by isEqual:, not by
   pointer. 10.9 has none of these appearances: appearanceNamed: returns nil for each. */
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101000
APPKIT_EXTERN NSString *const NSAppearanceNameVibrantDark;
APPKIT_EXTERN NSString *const NSAppearanceNameVibrantLight;
#endif
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101400
APPKIT_EXTERN NSString *const NSAppearanceNameDarkAqua;
APPKIT_EXTERN NSString *const NSAppearanceNameAccessibilityHighContrastAqua;
APPKIT_EXTERN NSString *const NSAppearanceNameAccessibilityHighContrastDarkAqua;
APPKIT_EXTERN NSString *const NSAppearanceNameAccessibilityHighContrastVibrantLight;
APPKIT_EXTERN NSString *const NSAppearanceNameAccessibilityHighContrastVibrantDark;
#endif

#endif
