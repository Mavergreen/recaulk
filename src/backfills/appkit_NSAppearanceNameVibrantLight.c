#include <CoreFoundation/CoreFoundation.h>

/* AppKit constant (added 10.10): an appearance's name, whose value is the name itself. 10.9's NSAppearance has no
   such appearance, so appearanceNamed: still returns nil for it. Not AppKit's pointer on 10.10+: compare with isEqual:. */
const CFStringRef NSAppearanceNameVibrantLight = CFSTR("NSAppearanceNameVibrantLight");
