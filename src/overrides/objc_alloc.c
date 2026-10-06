/*
 * ObjC runtime functions added in 10.14+ / 11.0+ --
 * custom polyfill (not from macports-legacy-support).
 */

#include <objc/objc.h>
#include <objc/message.h>
#include <objc/runtime.h>

/* objc_alloc (added ~10.14) — optimized [cls alloc] */
id objc_alloc(Class cls) {
	return ((id(*)(Class, SEL))objc_msgSend)(cls, sel_getUid("alloc"));
}
