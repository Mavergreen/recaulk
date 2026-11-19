/* spec: README.md "Swift's Dispatch" -- what Swift's importer sees through <dispatch/dispatch.h> on the 10.9 SDK:
   the 11.3 SDK's OS_OBJECT_SWIFT3 classes, backed by the classes 10.9's libdispatch registers. */
#include <dispatch/dispatch.h>
#include <objc/runtime.h> /* platform: #include, not #import: see the queue, "-fmodules #import of a wrapper" */
#include <stdio.h>
#include <string.h>

#ifdef __swift__
_Static_assert(__builtin_types_compatible_p(dispatch_queue_t, OS_dispatch_queue *), "dispatch_queue_t is a class");
_Static_assert(__builtin_types_compatible_p(dispatch_object_t, OS_dispatch_object *), "dispatch_object_t is a class");
_Static_assert(__builtin_types_compatible_p(dispatch_data_t, OS_dispatch_data *), "dispatch_data_t is a class");
/* Static upcasts along 10.9's runtime hierarchy compile. */
OS_dispatch_object *up_queue(dispatch_queue_t q) { return q; }
OS_object *up_object(dispatch_object_t o) { return o; }
NSObject *up_data(dispatch_data_t d) { return d; }
id<OS_dispatch_source_timer> up_timer(dispatch_source_t s) { return s; }
id<OS_dispatch_source_read> up_read(dispatch_source_t s) { return s; }
/* platform: under OS_OBJECT_SWIFT3 dispatch_retain stays a function (11.3's OS_OBJECT_USE_OBJC_RETAIN_RELEASE 0) */
#if OS_OBJECT_USE_OBJC_RETAIN_RELEASE
#error OS_OBJECT_USE_OBJC_RETAIN_RELEASE must be 0 for Swift
#endif
#endif

static int fail;
static int descends(Class c, const char *ancestor) {
    for (c = c ? class_getSuperclass(c) : Nil; c; c = class_getSuperclass(c))
        if (strcmp(class_getName(c), ancestor) == 0) return 1;
    return 0;
}
/* platform: with Foundation loaded, 10.9 reparents OS_dispatch_data under _NSDispatchData : NSData; a declared
   superclass need only be an ancestor, which objc_runtime_visible classes allow. */
static void super_is(const char *name, const char *super) {
    Class c = objc_getClass(name);
    if (!c) { printf("FAIL: no class %s at run time\n", name); fail = 1; return; }
    if (!descends(c, super)) { printf("FAIL: %s does not descend from %s\n", name, super); fail = 1; }
}
int main(void) {
    super_is("OS_object", "NSObject");
    super_is("OS_dispatch_object", "OS_object");
    super_is("OS_dispatch_queue", "OS_dispatch_object");
    super_is("OS_dispatch_group", "OS_dispatch_object");
    super_is("OS_dispatch_semaphore", "OS_dispatch_object");
    super_is("OS_dispatch_source", "OS_dispatch_object");
    super_is("OS_dispatch_io", "OS_dispatch_object");
    super_is("OS_dispatch_queue_attr", "OS_dispatch_object");
    super_is("OS_dispatch_data", "NSObject");
    if (descends(objc_getClass("OS_dispatch_data"), "OS_object")) { puts("FAIL: OS_dispatch_data descends from OS_object"); fail = 1; }
    dispatch_queue_t q = dispatch_queue_create("recaulk.swift-classes", NULL);
    if (![(id)q isKindOfClass:objc_getClass("OS_dispatch_queue")]) { puts("FAIL: a created queue is not an OS_dispatch_queue"); fail = 1; }
    dispatch_group_t g = dispatch_group_create();
    if (![(id)g isKindOfClass:objc_getClass("OS_dispatch_group")]) { puts("FAIL: a created group is not an OS_dispatch_group"); fail = 1; }
    dispatch_release(g); dispatch_release(q);
    if (!fail) puts("dispatch swift classes: 10.9's runtime has the declared hierarchy");
    return fail;
}
