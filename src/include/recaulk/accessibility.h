#ifndef RECAULK_ACCESSIBILITY_H
#define RECAULK_ACCESSIBILITY_H
#include <objc/objc.h>
#include <sys/cdefs.h>
__BEGIN_DECLS
/* 10.9's VoiceOver asks an element through the old attribute API (accessibilityAttributeNames,
 * accessibilityAttributeValue: and their kin), never through 10.10's NSAccessibility protocol getters. Call this once
 * per class of yours that implements only the 10.10 getters (an NSView or NSCell subclass), before any of its
 * instances is shown; the old API then answers from those getters, and from 10.9's own for anything they don't cover.
 * Pass the class literally: objc_getClass("Name") or [Name class]. Nil does nothing. A class that already implements
 * any of the old API methods itself, or whose app ancestor does, must not be passed. Librecaulk-objc.a. */
void recaulk_accessibility_bridge(Class cls);
__END_DECLS
#endif
