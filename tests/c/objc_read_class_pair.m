#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <objc/runtime.h>
#include <objc/message.h>

Class objc_readClassPair(Class cls, const void *info);
id objc_retain(id obj);
void objc_release(id obj);

#define RO_META          (1u << 0)
#define RO_HAS_CXX_STRUCTORS (1u << 2)
#define RO_HAS_CXX_DTOR_ONLY (1u << 8)
#define RW_HAS_CXX_CTOR  (1u << 20)
#define RW_HAS_CXX_DTOR  (1u << 19)
#define RW_REALIZED      (1u << 31)
#define RW_METHOD_ARRAY  (1u << 17)
#define RW_HAS_CUSTOM_AWZ (1u << 16)
#define RW_HAS_CUSTOM_RR (1u << 15)

/* objc4-551.1 runtime/objc-runtime-new.h: method_t, method_list_t, class_ro_t, objc_class (x86_64) */
struct rc_method { const char *name; const char *types; IMP imp; };
struct rc_mlist { uint32_t entsize; uint32_t count; struct rc_method m[2]; };
struct rc_ro {
    uint32_t flags, instanceStart, instanceSize, reserved;
    const uint8_t *ivarLayout;
    const char *name;
    const struct rc_mlist *baseMethods;
    const void *baseProtocols, *ivars;
    const uint8_t *weakIvarLayout;
    const void *baseProperties;
};
struct rc_class {
    struct rc_class *isa, *superclass;
    void *buckets;
    uint32_t mask, occupied;
    uintptr_t data;
};
struct rc_pair { struct rc_class cls, meta; struct rc_ro ro, metaro; struct rc_mlist ml; };

extern struct objc_cache _objc_empty_cache;

static uint32_t rw_flags(Class c) {
    return *(const uint32_t *)(((struct rc_class *)c)->data & ~(uintptr_t)3);
}

static long rr_count;

__attribute__((objc_root_class))
@interface RCRoot { Class isa; }
@end
@implementation RCRoot
+ (void)load { }
+ (void)initialize { }
- (id)retain { rr_count++; return self; }
- (oneway void)release { rr_count--; }
@end

static int answer(id self, SEL _cmd) { (void)self; (void)_cmd; return 42; }
static int twice(id self, SEL _cmd) { (void)self; (void)_cmd; return 84; }
static int added(id self, SEL _cmd) { (void)self; (void)_cmd; return 7; }
static void category_method(id self, SEL _cmd) { (void)self; (void)_cmd; }

static void fill_pair(struct rc_pair *p, const char *name, Class super, uint32_t nmethods) {
    struct rc_class *sup = (struct rc_class *)super;
    memset(p, 0, sizeof *p);
    p->ml.entsize = sizeof(struct rc_method);
    p->ml.count = nmethods;
    p->ml.m[0] = (struct rc_method){ "answer", "i16@0:8", (IMP)answer };
    p->ml.m[1] = (struct rc_method){ "twice", "i16@0:8", (IMP)twice };
    p->ro.instanceStart = p->ro.instanceSize = (uint32_t)class_getInstanceSize(super);
    p->ro.name = name;
    p->ro.baseMethods = nmethods ? &p->ml : NULL;
    p->metaro.flags = RO_META;
    p->metaro.instanceStart = p->metaro.instanceSize = (uint32_t)class_getInstanceSize(object_getClass((id)super));
    p->metaro.name = name;
    p->cls.isa = &p->meta;
    p->cls.superclass = sup;
    p->cls.buckets = &_objc_empty_cache;
    p->cls.data = (uintptr_t)&p->ro;
    p->meta.isa = sup->isa->isa;
    p->meta.superclass = sup->isa;
    p->meta.buckets = &_objc_empty_cache;
    p->meta.data = (uintptr_t)&p->metaro;
}

static Class read_pair(struct rc_pair *p) {
    Class cls = (Class)&p->cls;
    if (objc_readClassPair(cls, NULL) != cls) { printf("FAIL: objc_readClassPair did not return %s\n", p->ro.name); return Nil; }
    return cls;
}

static Class make_pair(struct rc_pair *p, const char *name, Class super, uint32_t nmethods) {
    fill_pair(p, name, super, nmethods);
    return read_pair(p);
}

static int check_inherited(const char *what, Class child) {
    uint32_t want = RW_REALIZED | (rw_flags(class_getSuperclass(child))
        & (RW_HAS_CUSTOM_RR | RW_HAS_CUSTOM_AWZ | RW_HAS_CXX_CTOR | RW_HAS_CXX_DTOR));
    uint32_t got = rw_flags(child);
    printf("%s: parent rw flags 0x%08x, child 0x%08x, want 0x%08x\n", what,
           rw_flags(class_getSuperclass(child)), got, want);
    if (got != want) { printf("FAIL: %s inherits flags other than its parent's RR, AWZ and C++ structor flags\n", what); return 1; }
    return 0;
}

static int test_nsobject_methods(void) {
    static struct rc_pair p;
    Class ns = objc_getClass("NSObject");
    if (!(rw_flags(ns) & RW_METHOD_ARRAY)) { printf("FAIL: NSObject has no categories attached, so this test proves nothing\n"); return 1; }
    Class cls = make_pair(&p, "RCNSChild", ns, 2);
    if (!cls) return 1;
    if (!class_addMethod(cls, sel_registerName("added"), (IMP)added, "i16@0:8")) { printf("FAIL: class_addMethod refused a new method\n"); return 1; }
    const char *names[] = { "answer", "twice", "added" };
    IMP imps[] = { (IMP)answer, (IMP)twice, (IMP)added };
    for (int i = 0; i < 3; i++) {
        Method m = class_getInstanceMethod(cls, sel_registerName(names[i]));
        if (!m || method_getImplementation(m) != imps[i]) { printf("FAIL: -%s does not resolve to its IMP\n", names[i]); return 1; }
    }
    id obj = class_createInstance(cls, 0);
    int a = ((int (*)(id, SEL))objc_msgSend)(obj, sel_registerName("answer"));
    int b = ((int (*)(id, SEL))objc_msgSend)(obj, sel_registerName("added"));
    if (a != 42 || b != 7) { printf("FAIL: messages to the realized class answered %d and %d, want 42 and 7\n", a, b); return 1; }
    printf("nsobject-methods: base, added and sent methods all resolve\n");
    return 0;
}

static int rr_balance(const char *what, Class root) {
    static struct rc_pair p[2];
    static int n;
    Class cls = make_pair(&p[n], n ? "RCRootChildB" : "RCRootChildA", root, 1);
    n++;
    if (!cls) return 1;
    if (!(rw_flags(cls) & RW_HAS_CUSTOM_RR)) { printf("FAIL: %s: the child of a custom-RR root lacks RW_HAS_CUSTOM_RR\n", what); return 1; }
    id obj = class_createInstance(cls, 0);
    rr_count = 0;
    objc_retain(obj);
    long after_retain = rr_count;
    objc_release(obj);
    printf("%s: -retain count %ld after objc_retain, %ld after objc_release\n", what, after_retain, rr_count);
    if (after_retain != 1 || rr_count != 0) { printf("FAIL: %s: objc_retain/objc_release bypassed the root's -retain/-release\n", what); return 1; }
    return 0;
}

static int test_custom_rr(void) {
    Class root = objc_getClass("RCRoot");
    if (!(rw_flags(root) & RW_HAS_CUSTOM_RR) || (rw_flags(root) & RW_METHOD_ARRAY)) {
        printf("FAIL: RCRoot rw flags 0x%08x are not SwiftObject's shape (RR, one method list)\n", rw_flags(root));
        return 1;
    }
    if (rr_balance("custom-rr", root)) return 1;
    class_addMethod(root, sel_registerName("categoryMethod"), (IMP)category_method, "v16@0:8");
    if (!(rw_flags(root) & RW_METHOD_ARRAY)) { printf("FAIL: RCRoot gained no method array\n"); return 1; }
    return rr_balance("custom-rr-with-category", root);
}

static int test_inherited_flags(void) {
    static struct rc_pair ns, rr;
    int fail = 0;
    Class a = make_pair(&ns, "RCFlagsNS", objc_getClass("NSObject"), 1);
    Class b = make_pair(&rr, "RCFlagsRR", objc_getClass("RCRoot"), 1);
    if (!a || !b) return 1;
    fail |= check_inherited("NSObject child", a);
    fail |= check_inherited("NSObject child's metaclass", object_getClass((id)a));
    fail |= check_inherited("RCRoot child", b);
    fail |= check_inherited("RCRoot child's metaclass", object_getClass((id)b));
    return fail;
}

extern int rc_cxx_ctor_count, rc_cxx_dtor_count;
static int own_ctor_count, own_dtor_count;
static id own_cxx_construct(id self, SEL _cmd) { (void)_cmd; own_ctor_count++; return self; }
static void own_cxx_destruct(id self, SEL _cmd) { (void)self; (void)_cmd; own_dtor_count++; }

static int structors(const char *what, Class cls, uint32_t want_flags, int *ctor, int *dtor, int want_ctor) {
    uint32_t got = rw_flags(cls) & (RW_HAS_CXX_CTOR | RW_HAS_CXX_DTOR);
    *ctor = *dtor = 0;
    id obj = class_createInstance(cls, 0);
    int ctors = *ctor;
    object_dispose(obj);
    printf("%s: C++ flags 0x%08x (want 0x%08x), %d constructed, %d destroyed\n", what, got, want_flags, ctors, *dtor);
    if (got != want_flags || ctors != want_ctor || *dtor != 1) {
        printf("FAIL: %s: objc did not run the .cxx_construct and .cxx_destruct its class or superclass declares\n", what);
        return 1;
    }
    return 0;
}

static int test_cxx(void) {
    static struct rc_pair inherit, own, dtor_only;
    int fail = 0;
    Class parent = objc_getClass("RCCxxParent");
    uint32_t both = RW_HAS_CXX_CTOR | RW_HAS_CXX_DTOR;
    if ((rw_flags(parent) & both) != both) { printf("FAIL: RCCxxParent lacks its C++ structor flags, so this test proves nothing\n"); return 1; }
    Class a = make_pair(&inherit, "RCCxxChild", parent, 1);
    if (!a) return 1;
    fail |= check_inherited("RCCxxParent child", a);
    fail |= structors("RCCxxParent child", a, both, &rc_cxx_ctor_count, &rc_cxx_dtor_count, 1);

    fill_pair(&own, "RCCxxOwn", objc_getClass("NSObject"), 2);
    own.ro.flags = RO_HAS_CXX_STRUCTORS;
    own.ml.m[0] = (struct rc_method){ ".cxx_construct", "@16@0:8", (IMP)own_cxx_construct };
    own.ml.m[1] = (struct rc_method){ ".cxx_destruct", "v16@0:8", (IMP)own_cxx_destruct };
    Class b = read_pair(&own);
    if (!b) return 1;
    fail |= structors("own .cxx_construct and .cxx_destruct", b, both, &own_ctor_count, &own_dtor_count, 1);

    fill_pair(&dtor_only, "RCCxxDtorOnly", objc_getClass("NSObject"), 1);
    dtor_only.ro.flags = RO_HAS_CXX_STRUCTORS | RO_HAS_CXX_DTOR_ONLY;
    dtor_only.ml.m[0] = (struct rc_method){ ".cxx_destruct", "v16@0:8", (IMP)own_cxx_destruct };
    Class c = read_pair(&dtor_only);
    if (!c) return 1;
    fail |= structors("own .cxx_destruct only", c, RW_HAS_CXX_DTOR, &own_ctor_count, &own_dtor_count, 0);
    return fail;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc != 2) return 2;
    if (!strcmp(argv[1], "nsobject-methods")) return test_nsobject_methods();
    if (!strcmp(argv[1], "custom-rr")) return test_custom_rr();
    if (!strcmp(argv[1], "inherited-flags")) return test_inherited_flags();
    if (!strcmp(argv[1], "cxx-structors")) return test_cxx();
    return 2;
}
