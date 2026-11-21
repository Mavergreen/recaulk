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
#include <string.h>

dispatch_queue_t __recaulk_dispatch_queue_create(const char *label, dispatch_queue_attr_t attr);
void __recaulk_dispatch_resume(dispatch_object_t object);
dispatch_queue_t __recaulk_dispatch_queue_create_targeted(const char *label, dispatch_queue_attr_t attr,
                                                          dispatch_queue_t target);
int objc_sync_enter(id);
int objc_sync_exit(id);

#define RECAULK_INACTIVE_MAGIC_V1 0x52434931u /* 'RCI1': an 8-byte struct, Recaulk 20261120.4 and earlier */
#define RECAULK_INACTIVE_MAGIC_V2 0x52434932u /* 'RCI2': the extra bytes of a RECAULK_INACTIVE_CLASS_V2 object */
#define RECAULK_INACTIVE_CLASS_V2 "__RecaulkDispatchInactiveQueueAttribute_v2"
#define RECAULK_ATTR_MAGIC_V4 0x52434934u     /* 'RCI4': the bytes of an attribute record, below */
struct inactive_attr { uint32_t magic; uint32_t concurrent; };

/* An attribute of Recaulk's: inactivity and a QoS class over a base, the system attribute the queue is made from,
   which carries its concurrency (and, on 10.10 and 10.11, the system's own QoS attribute). */
struct attr_v4 { uint32_t magic; int32_t inactive; int32_t qos; int32_t relpri; uintptr_t base; };

/* An association key, the selector of LITERAL, registered once. platform: Drydock's strict guard reads each
   sel_registerName argument and refuses one it cannot see as a single literal (fuse-gg, Recaulk 20261121.7), so
   every call site names its own literal; a helper taking the name would pass a register. */
#define KEY(LITERAL) ({ \
    static SEL k_; \
    SEL s_ = __atomic_load_n(&k_, __ATOMIC_ACQUIRE); \
    if (!s_) { s_ = sel_registerName(LITERAL); __atomic_store_n(&k_, s_, __ATOMIC_RELEASE); } \
    (const void *)s_; })
static const void *suspended_key(void) { return KEY("__recaulk_dispatch_inactive_v1"); }
static const void *activated_key(void) { return KEY("__recaulk_dispatch_activated_v1"); }

/* platform: kept out of line, each alone, so the compiler cannot merge their two sel_registerName calls into one
   whose argument is either literal, which the strict guard reads as computed */
__attribute__((noinline)) static const void *serial_attr_key(void) { return KEY("__recaulk_dispatch_inactive_attr_serial_v3"); }
__attribute__((noinline)) static const void *concurrent_attr_key(void) {
    return KEY("__recaulk_dispatch_inactive_attr_concurrent_v3");
}
static const void *attr_key(uint32_t concurrent) { return concurrent ? concurrent_attr_key() : serial_attr_key(); }

/* 20261121.7's serial or concurrent inactive attribute, a one-byte dispatch_data_t, when some copy made one. */
static id attr_published(uint32_t concurrent) {
    id holder = (id)objc_getClass("NSObject");
    objc_sync_enter(holder);
    id a = objc_getAssociatedObject(holder, attr_key(concurrent));
    objc_sync_exit(holder);
    return a;
}

static int is_kind(id object, const char *name, Class *cache) {
    Class k = __atomic_load_n(cache, __ATOMIC_ACQUIRE);
    if (!k) { k = objc_getClass(name); __atomic_store_n(cache, k, __ATOMIC_RELEASE); }
    for (Class c = object_getClass(object); k && c; c = class_getSuperclass(c))
        if (c == k) return 1;
    return 0;
}

/* The one record object per value, process-wide: every copy keeps them in one table, a CFMutableDictionary from the
   record's bytes to its object, published on NSObject's class object and used under that class object's lock, which
   all copies share. Records are never freed, so the table holds them without retaining. */
static id intern(const struct attr_v4 *a, int create) {
    id holder = (id)objc_getClass("NSObject");
    const void *tk = KEY("__recaulk_dispatch_attr_table_v4");
    objc_sync_enter(holder);
    CFMutableDictionaryRef t = (CFMutableDictionaryRef)objc_getAssociatedObject(holder, tk);
    if (!t && create) {
        if (!(t = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, NULL))) abort();
        objc_setAssociatedObject(holder, tk, (id)t, OBJC_ASSOCIATION_RETAIN);
        CFRelease(t);
    }
    id o = nil;
    if (t) {
        CFDataRef bytes = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)a, sizeof *a);
        if (!bytes) abort();
        o = (id)CFDictionaryGetValue(t, bytes);
        if (!o && create) {
            if (!(o = (id)dispatch_data_create(a, sizeof *a, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT))) abort();
            CFDictionarySetValue(t, bytes, (const void *)o);
        }
        CFRelease(bytes);
    }
    objc_sync_exit(holder);
    return o;
}

/* A record object is a dispatch_data_t of its bytes that intern() gives back for those bytes. */
static int read_v4(id o, struct attr_v4 *out) {
    static Class data;
    if (!is_kind(o, "OS_dispatch_data", &data)) return 0;
    dispatch_data_t d = (dispatch_data_t)o;
    if (dispatch_data_get_size(d) != sizeof *out) return 0;
    const void *p = NULL;
    size_t n = 0;
    dispatch_data_t m = dispatch_data_create_map(d, &p, &n);
    if (!m) return 0;
    int ok = n == sizeof *out;
    if (ok) memcpy(out, p, sizeof *out);
    dispatch_release(m);
    return ok && out->magic == RECAULK_ATTR_MAGIC_V4 && intern(out, 0) == o;
}

/* Fills *a for any attribute and returns 1 when it is Recaulk's; a system's becomes the base of an empty record.
   platform: 10.9's queue attributes are NULL (serial) and DISPATCH_QUEUE_CONCURRENT, an object; a later system's are
   objects too, whose first word is an isa, never the old magic, and whose class is never Recaulk's. */
static int parse(dispatch_queue_attr_t attr, struct attr_v4 *a) {
    memset(a, 0, sizeof *a);
    a->magic = RECAULK_ATTR_MAGIC_V4;
    a->base = (uintptr_t)attr;
    if (!attr || attr == DISPATCH_QUEUE_CONCURRENT) return 0;
    int concurrent = -1;
    /* the 20261120.4 struct is no object, so it is told apart before anything asks for a class */
    const struct inactive_attr *v1 = (const struct inactive_attr *)(const void *)attr;
    if (v1->magic == RECAULK_INACTIVE_MAGIC_V1) concurrent = v1->concurrent != 0;
    else if (read_v4((id)attr, a)) return 1;
    else {
        a->magic = RECAULK_ATTR_MAGIC_V4;
        a->base = (uintptr_t)attr;
        if ((id)attr == attr_published(0)) concurrent = 0;
        else if ((id)attr == attr_published(1)) concurrent = 1;
        else {
            /* platform: a RECAULK_INACTIVE_CLASS_V2 object is an NSObject subclass with no ivars, so its extra bytes
               follow the isa, where object_getIndexedIvars found them; the class is only looked up, never made */
            Class v2 = objc_getClass(RECAULK_INACTIVE_CLASS_V2);
            if (v2 && object_getClass((id)attr) == v2) {
                const struct inactive_attr *x =
                    (const struct inactive_attr *)(const void *)((const char *)(const void *)attr + sizeof(void *));
                if (x->magic == RECAULK_INACTIVE_MAGIC_V2) concurrent = x->concurrent != 0;
            }
        }
    }
    if (concurrent < 0) return 0;
    memset(a, 0, sizeof *a);
    a->magic = RECAULK_ATTR_MAGIC_V4;
    a->inactive = 1;
    a->base = concurrent ? (uintptr_t)DISPATCH_QUEUE_CONCURRENT : 0;
    return 1;
}

/* A record that adds nothing to its base is the base itself. */
static dispatch_queue_attr_t finish(const struct attr_v4 *a) {
    if (!a->inactive && !a->qos && !a->relpri) return (dispatch_queue_attr_t)a->base;
    return (dispatch_queue_attr_t)intern(a, 1);
}

/* platform: the system libdispatch's own copy of a call it may lack (10.9 lacks both of these), looked up there
   rather than by RTLD_NEXT, which would find another copy of Recaulk */
static void *system_dispatch(const char *name) {
    void *h = dlopen("/usr/lib/system/libdispatch.dylib", RTLD_LAZY | RTLD_NOLOAD);
    return h ? dlsym(h, name) : NULL;
}

dispatch_queue_attr_t dispatch_queue_attr_make_initially_inactive(dispatch_queue_attr_t attr) {
    struct attr_v4 a;
    (void)parse(attr, &a);
    a.inactive = 1;
    return finish(&a);
}

/* dispatch_queue_attr_make_with_qos_class's work (src/backfills/dispatch_attr_qos.c, its own member): given a system
   attribute, the system's call where there is one; given Recaulk's, the system's call, where there is one, applied
   to the base, and the record keeps the class too, so a queue made from it on 10.9 reports it (swift-gg, 2026-11-20). */
__attribute__((visibility("hidden"))) dispatch_queue_attr_t __recaulk_dispatch_attr_with_qos(dispatch_queue_attr_t attr,
    dispatch_qos_class_t qos_class, int relative_priority);
__attribute__((visibility("hidden"))) dispatch_queue_attr_t __recaulk_dispatch_attr_with_qos(dispatch_queue_attr_t attr,
    dispatch_qos_class_t qos_class, int relative_priority) {
    typedef dispatch_queue_attr_t make_qos_fn(dispatch_queue_attr_t, dispatch_qos_class_t, int);
    static make_qos_fn *system;
    static int looked;
    if (!__atomic_load_n(&looked, __ATOMIC_ACQUIRE)) {
        __atomic_store_n(&system, (make_qos_fn *)system_dispatch("dispatch_queue_attr_make_with_qos_class"), __ATOMIC_RELEASE);
        __atomic_store_n(&looked, 1, __ATOMIC_RELEASE);
    }
    make_qos_fn *f = __atomic_load_n(&system, __ATOMIC_ACQUIRE);
    struct attr_v4 a;
    if (!parse(attr, &a)) {
        if (f) return f(attr, qos_class, relative_priority);
    } else if (f) {
        a.base = (uintptr_t)f((dispatch_queue_attr_t)a.base, qos_class, relative_priority);
    }
    a.qos = (int32_t)qos_class;
    a.relpri = relative_priority;
    return finish(&a);
}

static const void *qos_key(void) { return KEY("__recaulk_dispatch_qos_v4"); }

/* dispatch_queue_get_qos_class (10.10), forwarded to the system's where there is one: on 10.9, the class and relative
   priority the queue's attribute named, kept on the queue, else QOS_CLASS_UNSPECIFIED and 0, as Recaulk's pthread
   QoS calls answer. */
dispatch_qos_class_t dispatch_queue_get_qos_class(dispatch_queue_t queue, int *relative_priority_ptr) {
    CFNumberRef n = queue ? (CFNumberRef)objc_getAssociatedObject((id)queue, qos_key()) : NULL;
    int64_t v = 0;
    if (n) CFNumberGetValue(n, kCFNumberSInt64Type, &v);
    if (relative_priority_ptr) *relative_priority_ptr = n ? (int)(v & 0xff) - 128 : 0;
    return n ? (dispatch_qos_class_t)(v >> 8) : QOS_CLASS_UNSPECIFIED;
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
    struct attr_v4 a;
    if (!parse(attr, &a)) {
        dispatch_queue_t q = system_create(label, attr);
        if (q && target) dispatch_set_target_queue(q, target);
        return q;
    }
    dispatch_queue_t q = system_create(label, (dispatch_queue_attr_t)a.base);
    if (!q) return q;
    if (target) dispatch_set_target_queue(q, target);
    if (a.qos || a.relpri) {
        int64_t v = ((int64_t)a.qos << 8) | (int64_t)((a.relpri + 128) & 0xff);
        CFNumberRef n = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &v);
        if (n) { objc_setAssociatedObject((id)q, qos_key(), (id)n, OBJC_ASSOCIATION_RETAIN); CFRelease(n); }
    }
    if (a.inactive) {
        dispatch_suspend(q);
        objc_setAssociatedObject((id)q, suspended_key(), (id)kCFBooleanTrue, OBJC_ASSOCIATION_RETAIN);
    }
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
