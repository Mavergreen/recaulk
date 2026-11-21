/*
 * Initially inactive queues and dispatch_activate (10.12), on 10.9. README.md "Dispatch on 10.9".
 *
 * dispatch_queue_attr_make_initially_inactive returns one of two attributes of Recaulk's own, serial or
 * concurrent, and dispatch_queue_create given one creates the queue suspended and marks it. dispatch_activate
 * resumes a marked queue once, and a source once (10.9's sources start suspended, as 10.12's start inactive);
 * on any other object it does nothing, as 10.12's does on an active one. A second dispatch_activate changes
 * nothing, where a second dispatch_resume would trap. A dispatch_resume of either is its activation, as on 10.12,
 * so a dispatch_activate after it does nothing too. A source suspended and resumed before it ever started counts
 * as started, which 10.9 cannot tell apart.
 *
 * Every copy of Recaulk in a process agrees on both. An attribute is an Objective-C object, because Swift and ARC
 * code retain and release every dispatch_queue_attr_t (an 8-byte struct there crashed objc_retain, which read its
 * magic as an isa: swift-gg, 10.9.5, 20261120.3). Its class is registered by name, once per process, so every copy
 * finds the same one, and it carries a magic number and its concurrency in its extra bytes. The 'RCI1' structs of
 * Recaulk 20261120.4 and earlier are still told apart by their magic. The marks are associated objects keyed by a
 * selector, one pointer per name process-wide, as dispatch_modern.c's block state is. platform: measured on 10.9.5, a queue or source releases its associated
 * objects when it is freed, so a new object at a freed one's address starts unmarked.
 *
 * dispatch_queue_create and dispatch_resume are 10.9 exports, so here they are weak and hidden (build/image-local-shadows.txt): it binds
 * only inside the image that links librecaulk.a, and yields to the public one src/overrides/dispatch_inactive_export.c
 * gives libRecaulkSystem.dylib. Given any attribute but Recaulk's, dispatch_queue_create is the system's.
 */
#include <dispatch/dispatch.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <stdint.h>
#include <stdlib.h>

dispatch_queue_t __recaulk_dispatch_queue_create(const char *label, dispatch_queue_attr_t attr);
void __recaulk_dispatch_resume(dispatch_object_t object);
dispatch_queue_t __recaulk_dispatch_queue_create_targeted(const char *label, dispatch_queue_attr_t attr,
                                                          dispatch_queue_t target);
int objc_sync_enter(id);
int objc_sync_exit(id);

#define RECAULK_INACTIVE_MAGIC_V1 0x52434931u /* 'RCI1': an 8-byte struct, Recaulk 20261120.4 and earlier */
#define RECAULK_INACTIVE_MAGIC 0x52434932u    /* 'RCI2': the extra bytes of an object of RECAULK_INACTIVE_CLASS */
#define RECAULK_INACTIVE_CLASS "__RecaulkDispatchInactiveQueueAttribute_v2"
struct inactive_attr { uint32_t magic; uint32_t concurrent; };

/* The class, registered by the first copy of Recaulk to ask; NULL until one has, when no attribute is ours. Every
   copy registers under the one lock of NSObject's class object, which they share. */
static Class attr_class(int create) {
    static Class cached;
    Class c = __atomic_load_n(&cached, __ATOMIC_ACQUIRE);
    if (c) return c;
    if (!(c = objc_getClass(RECAULK_INACTIVE_CLASS)) && create) {
        id lock = (id)objc_getClass("NSObject");
        objc_sync_enter(lock);
        if (!(c = objc_getClass(RECAULK_INACTIVE_CLASS))) {
            c = objc_allocateClassPair(objc_getClass("NSObject"), RECAULK_INACTIVE_CLASS, 0);
            if (c) objc_registerClassPair(c);
        }
        objc_sync_exit(lock);
    }
    if (c) __atomic_store_n(&cached, c, __ATOMIC_RELEASE);
    return c;
}

/* This copy's serial or concurrent attribute, made once and never freed: retains and releases stay balanced. */
static dispatch_queue_attr_t attr_object(uint32_t concurrent) {
    static id made[2];
    id a = __atomic_load_n(&made[concurrent], __ATOMIC_ACQUIRE);
    if (a) return (dispatch_queue_attr_t)a;
    Class c = attr_class(1);
    if (!c || !(a = class_createInstance(c, sizeof(struct inactive_attr)))) abort();
    struct inactive_attr *ia = object_getIndexedIvars(a);
    ia->magic = RECAULK_INACTIVE_MAGIC;
    ia->concurrent = concurrent;
    id expected = nil;
    if (!__atomic_compare_exchange_n(&made[concurrent], &expected, a, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        object_dispose(a);
        a = expected;
    }
    return (dispatch_queue_attr_t)a;
}

/* platform: 10.9's queue attributes are NULL (serial) and DISPATCH_QUEUE_CONCURRENT, an object; a later system's are
   objects too, whose first word is an isa, never the old magic, and whose class is never Recaulk's. */
static const struct inactive_attr *inactive(dispatch_queue_attr_t attr) {
    if (!attr || attr == DISPATCH_QUEUE_CONCURRENT) return NULL;
    const struct inactive_attr *v1 = (const struct inactive_attr *)(const void *)attr;
    if (v1->magic == RECAULK_INACTIVE_MAGIC_V1) return v1;
    Class c = attr_class(0);
    if (!c || object_getClass((id)attr) != c) return NULL;
    const struct inactive_attr *a = object_getIndexedIvars((id)attr);
    return a->magic == RECAULK_INACTIVE_MAGIC ? a : NULL;
}

dispatch_queue_attr_t dispatch_queue_attr_make_initially_inactive(dispatch_queue_attr_t attr) {
    const struct inactive_attr *a = inactive(attr);
    if (a) return a->magic == RECAULK_INACTIVE_MAGIC ? attr : attr_object(a->concurrent ? 1 : 0);
    return attr_object(attr == DISPATCH_QUEUE_CONCURRENT ? 1 : 0);
}

static const void *key(const char *name, SEL *cache) {
    SEL k = __atomic_load_n(cache, __ATOMIC_ACQUIRE);
    if (!k) { k = sel_registerName(name); __atomic_store_n(cache, k, __ATOMIC_RELEASE); }
    return (const void *)k;
}
static const void *suspended_key(void) { static SEL k; return key("__recaulk_dispatch_inactive_v1", &k); }
static const void *activated_key(void) { static SEL k; return key("__recaulk_dispatch_activated_v1", &k); }

typedef dispatch_queue_t queue_create_fn(const char *, dispatch_queue_attr_t);

static dispatch_queue_t system_create(const char *label, dispatch_queue_attr_t attr) {
    static queue_create_fn *system;
    queue_create_fn *f = __atomic_load_n(&system, __ATOMIC_ACQUIRE);
    if (!f) {
        f = (queue_create_fn *)dlsym(RTLD_NEXT, "dispatch_queue_create");
        __atomic_store_n(&system, f, __ATOMIC_RELEASE);
    }
    return f(label, attr);
}

dispatch_queue_t __recaulk_dispatch_queue_create_targeted(const char *label, dispatch_queue_attr_t attr,
                                                          dispatch_queue_t target) {
    const struct inactive_attr *a = inactive(attr);
    if (!a) {
        dispatch_queue_t q = system_create(label, attr);
        if (q && target) dispatch_set_target_queue(q, target);
        return q;
    }
    dispatch_queue_t q = system_create(label, a->concurrent ? DISPATCH_QUEUE_CONCURRENT : DISPATCH_QUEUE_SERIAL);
    if (!q) return q;
    if (target) dispatch_set_target_queue(q, target);
    dispatch_suspend(q);
    objc_setAssociatedObject((id)q, suspended_key(), (id)kCFBooleanTrue, OBJC_ASSOCIATION_RETAIN);
    return q;
}

dispatch_queue_t __recaulk_dispatch_queue_create(const char *label, dispatch_queue_attr_t attr) {
    return __recaulk_dispatch_queue_create_targeted(label, attr, NULL);
}

__attribute__((weak, visibility("hidden"))) dispatch_queue_t recaulk_dispatch_queue_create(const char *,
    dispatch_queue_attr_t) __asm("_dispatch_queue_create");
__attribute__((weak, visibility("hidden"))) dispatch_queue_t recaulk_dispatch_queue_create(const char *label,
                                                                                           dispatch_queue_attr_t attr) {
    return __recaulk_dispatch_queue_create(label, attr);
}

static int is_source(id object) {
    static Class source;
    Class s = __atomic_load_n(&source, __ATOMIC_ACQUIRE);
    if (!s) { s = objc_getClass("OS_dispatch_source"); __atomic_store_n(&source, s, __ATOMIC_RELEASE); }
    for (Class c = object_getClass(object); s && c; c = class_getSuperclass(c))
        if (c == s) return 1;
    return 0;
}

/* Takes the object's one activation: 1 when it was a queue made inactive or a source not yet started. */
static int take_activation(id o) {
    int taken = 0;
    objc_sync_enter(o);
    if (objc_getAssociatedObject(o, suspended_key())) {
        objc_setAssociatedObject(o, suspended_key(), nil, OBJC_ASSOCIATION_RETAIN);
        taken = 1;
    } else if (is_source(o) && !objc_getAssociatedObject(o, activated_key())) {
        objc_setAssociatedObject(o, activated_key(), (id)kCFBooleanTrue, OBJC_ASSOCIATION_RETAIN);
        taken = 1;
    }
    objc_sync_exit(o);
    return taken;
}

typedef void resume_fn(dispatch_object_t);

static void system_resume(dispatch_object_t object) {
    static resume_fn *system;
    resume_fn *f = __atomic_load_n(&system, __ATOMIC_ACQUIRE);
    if (!f) {
        f = (resume_fn *)dlsym(RTLD_NEXT, "dispatch_resume");
        __atomic_store_n(&system, f, __ATOMIC_RELEASE);
    }
    f(object);
}

void dispatch_activate(dispatch_object_t object) {
    id o = (id)object._do;
    if (o && take_activation(o)) system_resume(object);
}

/* A dispatch_resume of a queue made inactive or of a source not yet started is its activation, as on 10.12, so a
 * dispatch_activate after it does nothing; any other resume is the system's alone. */
void __recaulk_dispatch_resume(dispatch_object_t object) {
    id o = (id)object._do;
    if (o) (void)take_activation(o);
    system_resume(object);
}

__attribute__((weak, visibility("hidden"))) void recaulk_dispatch_resume(dispatch_object_t) __asm("_dispatch_resume");
__attribute__((weak, visibility("hidden"))) void recaulk_dispatch_resume(dispatch_object_t object) {
    __recaulk_dispatch_resume(object);
}
