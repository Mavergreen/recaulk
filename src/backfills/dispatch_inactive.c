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
 * magic as an isa: swift-gg, 10.9.5, 20261120.3). Each is a one-byte dispatch_data_t, made by the first copy to ask
 * and published process-wide as an associated object of NSObject's class object, keyed by a selector; a copy
 * recognises one by identity, never by its contents. Recaulk makes no class: Drydock's strict guard cannot model one
 * made at run time, and refuses class_createInstance, object_getIndexedIvars and object_dispose (fuse-gg, 2026-11-21),
 * and a class compiled into librecaulk.a would exist once per image, which 10.9's runtime reports as a duplicate.
 * Still told apart: the 'RCI1' structs of Recaulk 20261120.4 and earlier, by their magic, and the objects of
 * 20261121.1-.6's class __RecaulkDispatchInactiveQueueAttribute_v2, by that class. The marks are associated objects keyed by a
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
#define RECAULK_INACTIVE_MAGIC_V2 0x52434932u /* 'RCI2': the extra bytes of a RECAULK_INACTIVE_CLASS_V2 object */
#define RECAULK_INACTIVE_CLASS_V2 "__RecaulkDispatchInactiveQueueAttribute_v2"
struct inactive_attr { uint32_t magic; uint32_t concurrent; };

static const void *key(const char *name, SEL *cache) {
    SEL k = __atomic_load_n(cache, __ATOMIC_ACQUIRE);
    if (!k) { k = sel_registerName(name); __atomic_store_n(cache, k, __ATOMIC_RELEASE); }
    return (const void *)k;
}
static const void *suspended_key(void) { static SEL k; return key("__recaulk_dispatch_inactive_v1", &k); }
static const void *activated_key(void) { static SEL k; return key("__recaulk_dispatch_activated_v1", &k); }

static const void *attr_key(uint32_t concurrent) {
    static SEL k[2];
    return key(concurrent ? "__recaulk_dispatch_inactive_attr_concurrent_v3" : "__recaulk_dispatch_inactive_attr_serial_v3",
               &k[concurrent]);
}

/* The process's serial or concurrent attribute, or NULL when no copy has made it. Every copy publishes it under the
   one lock of NSObject's class object, which they share, and it is never freed: retains and releases stay balanced. */
static id attr_published(uint32_t concurrent, int create) {
    static id cached[2];
    id a = __atomic_load_n(&cached[concurrent], __ATOMIC_ACQUIRE);
    if (a) return a;
    id holder = (id)objc_getClass("NSObject");
    objc_sync_enter(holder);
    if (!(a = objc_getAssociatedObject(holder, attr_key(concurrent))) && create) {
        uint8_t byte = (uint8_t)concurrent;
        a = (id)dispatch_data_create(&byte, 1, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        if (!a) abort();
        objc_setAssociatedObject(holder, attr_key(concurrent), a, OBJC_ASSOCIATION_RETAIN);
        dispatch_release((dispatch_object_t)(dispatch_data_t)a);
    }
    objc_sync_exit(holder);
    if (a) __atomic_store_n(&cached[concurrent], a, __ATOMIC_RELEASE);
    return a;
}

/* 1 for an attribute that makes a serial inactive queue, 2 for a concurrent one, 0 for any other.
   platform: 10.9's queue attributes are NULL (serial) and DISPATCH_QUEUE_CONCURRENT, an object; a later system's are
   objects too, whose first word is an isa, never the old magic, and whose class is never Recaulk's. */
static int inactive(dispatch_queue_attr_t attr) {
    if (!attr || attr == DISPATCH_QUEUE_CONCURRENT) return 0;
    if ((id)attr == attr_published(0, 0)) return 1;
    if ((id)attr == attr_published(1, 0)) return 2;
    const struct inactive_attr *v1 = (const struct inactive_attr *)(const void *)attr;
    if (v1->magic == RECAULK_INACTIVE_MAGIC_V1) return v1->concurrent ? 2 : 1;
    /* platform: a RECAULK_INACTIVE_CLASS_V2 object is an NSObject subclass with no ivars, so its extra bytes follow
       the isa, where object_getIndexedIvars found them; the class is only looked up, never made */
    Class v2 = objc_getClass(RECAULK_INACTIVE_CLASS_V2);
    if (v2 && object_getClass((id)attr) == v2) {
        const struct inactive_attr *a = (const struct inactive_attr *)(const void *)((const char *)(const void *)attr + sizeof(void *));
        if (a->magic == RECAULK_INACTIVE_MAGIC_V2) return a->concurrent ? 2 : 1;
    }
    return 0;
}

dispatch_queue_attr_t dispatch_queue_attr_make_initially_inactive(dispatch_queue_attr_t attr) {
    int a = inactive(attr);
    uint32_t concurrent = a ? (a == 2) : (attr == DISPATCH_QUEUE_CONCURRENT);
    return (dispatch_queue_attr_t)attr_published(concurrent, 1);
}

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
    int a = inactive(attr);
    if (!a) {
        dispatch_queue_t q = system_create(label, attr);
        if (q && target) dispatch_set_target_queue(q, target);
        return q;
    }
    dispatch_queue_t q = system_create(label, a == 2 ? DISPATCH_QUEUE_CONCURRENT : DISPATCH_QUEUE_SERIAL);
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
