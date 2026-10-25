/*
 * objc_readClassPair for OS X 10.9 -- kept in its own translation unit.
 *
 * A consumer must ask for this symbol deliberately, because merely defining it
 * changes behaviour elsewhere. The ModernMavericks Swift runtime checks at run
 * time whether objc_readClassPair exists and, when it does, hands class
 * realization to it -- bypassing the realization it does itself, which is the
 * path that project validated on real 10.9. Linking this in by accident, as a
 * side effect of pulling some neighbouring objc helper out of the same object
 * file, silently swaps a tested code path for this one.
 *
 * So: link it only where nothing else provides class realization.
 *
 */

#include <stdlib.h>
#include <stdint.h>
#include <objc/objc.h>
#include <objc/runtime.h>

/* objc4-551.1 class_rw_t (x86_64), 56 bytes. */
struct mpls_objc_class_rw {
    uint32_t flags;
    uint32_t version;
    const void *ro;
    void *method_list_or_lists;
    void *properties;
    const void *protocols;
    void *firstSubclass;
    void *nextSiblingClass;
};

/* objc4-551.1 objc_class (x86_64), 40 bytes: cache_t is inline, with no vtable. */
struct mpls_objc_class {
    struct mpls_objc_class *isa;
    struct mpls_objc_class *superclass;
    void *cache_buckets;
    uint32_t cache_shiftmask;
    uint32_t cache_occupied;
    uintptr_t data_NEVER_USE;   /* data() is this with the low 2 bits masked */
};

#define MPLS_RW_REALIZED (1u << 31)

/* objc4-551.1 addSubclass() propagates these from the superclass when it
 * realizes a class, and the minimal realization below has to do the same.
 * RR is the most important: it marks the class as having its own retain/release,
 * which makes objc_retain send -retain instead of using libobjc's side table.
 *
 * A Swift class inherits retain/release from SwiftObject, so it must carry
 * this bit. Without it, ObjC retains land in the side table while Swift's own
 * retains land in the object header -- two counters for one object, and the
 * object is released twice, which surfaces as
 *
 *   malloc: *** error for object 0x...: pointer being freed was not allocated
 *
 * on the first Dictionary or Set to cross into Objective-C.
 *
 * Values: objc4-551.1 runtime/objc-runtime-new.h, the objc4 in OS X 10.9.
 * Bit 17 there is RW_METHOD_ARRAY, which must never be inherited. */
#define MPLS_RW_HAS_CUSTOM_RR  (1u << 15)
#define MPLS_RW_HAS_CUSTOM_AWZ (1u << 16)

/* Without these, objc skips this class's .cxx_construct and .cxx_destruct and
 * every superclass's, which is where Swift initializes and destroys the stored
 * properties of a class with Objective-C ancestry. realizeClass() sets them
 * from the ro's flags and addSubclass() from the superclass's (objc4-551.1
 * runtime/objc-runtime-new.mm, lines 1846-1852 and 1388-1394; values from its
 * objc-runtime-new.h). */
#define MPLS_RW_HAS_CXX_DTOR (1u << 19)
#define MPLS_RW_HAS_CXX_CTOR (1u << 20)
#define MPLS_RO_HAS_CXX_STRUCTORS (1u << 2)
#define MPLS_RO_HAS_CXX_DTOR_ONLY (1u << 8)

#define MPLS_RW_INHERITED_MASK (MPLS_RW_HAS_CUSTOM_RR | MPLS_RW_HAS_CUSTOM_AWZ \
                                | MPLS_RW_HAS_CXX_CTOR | MPLS_RW_HAS_CXX_DTOR)

extern struct objc_cache _objc_empty_cache;

/* Flags a realized class carries that a newly realized subclass must inherit.
 * Returns 0 if the superclass is missing or not itself realized yet. */
static uint32_t mpls_inherited_flags(struct mpls_objc_class *cls) {
    if (!cls || !cls->superclass) return 0;
    uintptr_t data = cls->superclass->data_NEVER_USE;
    struct mpls_objc_class_rw *super_rw =
        (struct mpls_objc_class_rw *)(data & ~(uintptr_t)3);
    if (!super_rw || !(super_rw->flags & MPLS_RW_REALIZED)) return 0;
    return super_rw->flags & MPLS_RW_INHERITED_MASK;
}

static uint32_t mpls_ro_cxx_flags(const void *ro) {
    uint32_t ro_flags = *(const uint32_t *)ro;
    if (!(ro_flags & MPLS_RO_HAS_CXX_STRUCTORS)) return 0;
    if (ro_flags & MPLS_RO_HAS_CXX_DTOR_ONLY) return MPLS_RW_HAS_CXX_DTOR;
    return MPLS_RW_HAS_CXX_DTOR | MPLS_RW_HAS_CXX_CTOR;
}

static void mpls_minimal_realize(void *clsPtr) {
    struct mpls_objc_class *cls = (struct mpls_objc_class *)clsPtr;
    if (!cls) return;

    uintptr_t data = cls->data_NEVER_USE;
    struct mpls_objc_class_rw *maybeRW =
        (struct mpls_objc_class_rw *)(data & ~(uintptr_t)3);

    /* An unrealized class still points at its ro, whose flags never have bit 31
     * set -- so this both detects the ro case and skips a class already done. */
    if (maybeRW && (maybeRW->flags & MPLS_RW_REALIZED)) return;

    const void *ro = maybeRW;
    if (!ro) return;
    struct mpls_objc_class_rw *rw = calloc(1, sizeof *rw);
    if (!rw) return;
    /* One method list, so no RW_METHOD_ARRAY. */
    rw->flags = MPLS_RW_REALIZED | mpls_inherited_flags(cls) | mpls_ro_cxx_flags(ro);
    rw->version = 0;
    rw->ro = ro;

    cls->cache_buckets = &_objc_empty_cache;
    cls->cache_shiftmask = 0;
    cls->cache_occupied = 0;
    /* setData, preserving the is-swift low bits, as objc4-551.1's does. */
    cls->data_NEVER_USE = (uintptr_t)rw | (data & (uintptr_t)3);
}

/* objc4-551.1 class_ro_t (x86_64): baseMethods sits at offset 32. */
struct mpls_objc_method {
    void *name;          /* a SEL once registered; a char* before that */
    const char *types;
    IMP imp;
};
struct mpls_objc_method_list {
    uint32_t entsize_and_flags;
    uint32_t count;
    struct mpls_objc_method first;
};

/* Realizing the class is not enough on its own: objc4-551.1 builds a realized
 * class's method list during realizeClass, and the minimal realization above
 * leaves it empty. A class with no methods answers nothing, so a Swift generic
 * class standing in for NSDictionary fails as
 *
 *   -[NSDictionary count]: method only defined for abstract class
 *
 * the moment Foundation asks it anything. Rather than reproduce objc4-551.1's
 * method-list layout -- which varies with whether categories have been
 * attached -- the methods are handed to objc through class_addMethod, which
 * builds whatever representation this runtime uses and updates the class's
 * flags as it goes.
 *
 * A method name is a char * before objc registers it and a SEL afterwards, and
 * a SEL is a pointer to that same string, so sel_registerName accepts either. */
static void mpls_attach_base_methods(Class cls) {
    if (!cls) return;
    struct mpls_objc_class *c = (struct mpls_objc_class *)cls;
    struct mpls_objc_class_rw *rw =
        (struct mpls_objc_class_rw *)(c->data_NEVER_USE & ~(uintptr_t)3);
    if (!rw || !rw->ro) return;

    struct mpls_objc_method_list *ml =
        *(struct mpls_objc_method_list **)((const char *)rw->ro + 32);
    if (!ml || !ml->count) return;

    uint32_t entsize = ml->entsize_and_flags & ~(uint32_t)3;
    if (entsize < sizeof(struct mpls_objc_method)) return;

    const char *base = (const char *)&ml->first;
    for (uint32_t i = 0; i < ml->count; i++) {
        struct mpls_objc_method *m =
            (struct mpls_objc_method *)(base + (size_t)i * entsize);
        if (!m->name || !m->imp) continue;
        class_addMethod(cls, sel_registerName((const char *)m->name),
                        m->imp, m->types);
    }
}

Class objc_readClassPair(Class cls, const void *info) {
    (void)info;
    if (!cls) return Nil;
    /* Both halves of the pair: the class and its metaclass. */
    mpls_minimal_realize((void *)cls);
    mpls_minimal_realize((void *)object_getClass((id)cls));
    /* Instance methods on the class, class methods on the metaclass. */
    mpls_attach_base_methods(cls);
    mpls_attach_base_methods((Class)object_getClass((id)cls));
    /* The caller asserts the returned class is the one it passed in. */
    return cls;
}
