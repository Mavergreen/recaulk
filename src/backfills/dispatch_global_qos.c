/*
 * dispatch_get_global_queue given a QoS class. 10.10's libdispatch takes either a priority or a QoS class; 10.9's
 * knows only the four priorities and returns NULL for a class (MEASURED by swift on 10.9.5: 0x15 gives NULL).
 * So when the system's answer is NULL for a class, this asks again with the priority 10.10's own queue.h pairs it
 * with: user-interactive and user-initiated HIGH, default DEFAULT, utility LOW, background and maintenance
 * BACKGROUND. On a system that knows the classes the first answer stands. README.md "Dispatch on 10.9".
 *
 * dispatch_get_global_queue is a 10.9 export, so here it is weak and hidden (build/image-local-shadows.txt): it
 * binds only inside the image that links librecaulk.a, and yields to the public one
 * src/overrides/dispatch_global_qos_export.c gives libRecaulkSystem.dylib.
 */
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <pthread/qos.h>

dispatch_queue_t __recaulk_dispatch_get_global_queue(long identifier, unsigned long flags);

typedef dispatch_queue_t global_queue_fn(long, unsigned long);

static long priority_for(long identifier) {
    switch (identifier) {
    case QOS_CLASS_USER_INTERACTIVE: case QOS_CLASS_USER_INITIATED: return DISPATCH_QUEUE_PRIORITY_HIGH;
    case QOS_CLASS_DEFAULT: return DISPATCH_QUEUE_PRIORITY_DEFAULT;
    case QOS_CLASS_UTILITY: return DISPATCH_QUEUE_PRIORITY_LOW;
    case QOS_CLASS_BACKGROUND: case 0x05 /* QOS_CLASS_MAINTENANCE, private */: return DISPATCH_QUEUE_PRIORITY_BACKGROUND;
    default: return identifier;
    }
}

dispatch_queue_t __recaulk_dispatch_get_global_queue(long identifier, unsigned long flags) {
    static global_queue_fn *system;
    global_queue_fn *f = __atomic_load_n(&system, __ATOMIC_ACQUIRE);
    if (!f) {
        f = (global_queue_fn *)dlsym(RTLD_NEXT, "dispatch_get_global_queue");
        __atomic_store_n(&system, f, __ATOMIC_RELEASE);
    }
    dispatch_queue_t q = f(identifier, flags);
    long priority = priority_for(identifier);
    return q || priority == identifier ? q : f(priority, flags);
}

__attribute__((weak, visibility("hidden"))) dispatch_queue_t recaulk_dispatch_get_global_queue(long, unsigned long)
    __asm("_dispatch_get_global_queue");
__attribute__((weak, visibility("hidden"))) dispatch_queue_t recaulk_dispatch_get_global_queue(long identifier,
                                                                                               unsigned long flags) {
    return __recaulk_dispatch_get_global_queue(identifier, flags);
}
