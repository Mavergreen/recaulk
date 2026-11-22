/*
 * __NSDictionary0__struct (a later CoreFoundation's): the shared empty NSDictionary that a newer SDK's clang emits
 * for @{} as the address of this storage. 10.9's CoreFoundation lacks it, so the storage is
 * here, and a constructor builds in it an instance of the class 10.9's own empty NSDictionary has: an immutable
 * empty collection, built in place by objc_constructInstance (no instance's bytes are copied). It is never
 * freed: nothing owns it, so balanced retains and releases leave it alive.
 */
#include <objc/message.h>
#include <objc/runtime.h>

/* platform: an Objective-C instance is 16-byte aligned; 10.9's empty immutable collections are 16 bytes */
__attribute__((aligned(16))) char __NSDictionary0__struct[64];

__attribute__((constructor)) static void recaulk_empty_dictionary(void) {
    /* platform: a dylib's initializer runs after those of the libraries it links, so CoreFoundation's
     * classes are ready; alloc/init, not +dictionary, since no autorelease pool exists yet */
    Class ns = objc_getClass("NSDictionary");
    if (!ns) return;
    id empty = ((id (*)(id, SEL))objc_msgSend)((id)ns, sel_registerName("alloc"));
    empty = ((id (*)(id, SEL))objc_msgSend)(empty, sel_registerName("init"));
    if (!empty) return;
    Class cls = object_getClass(empty);
    if (class_getInstanceSize(cls) <= sizeof __NSDictionary0__struct)
        objc_constructInstance(cls, __NSDictionary0__struct);
    ((void (*)(id, SEL))objc_msgSend)(empty, sel_registerName("release"));
}
