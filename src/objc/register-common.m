/* No messages, framework loading or dynamic method resolution here: the runtime's C API only. */
#import "register-common.h"
#include <stdlib.h>
__attribute__((visibility("hidden")))
void __recaulk_objc_add_method(Class receiver, const char *name, IMP imp, const char *encoding) {
    if (!receiver) return;
    SEL selector=sel_registerName(name);
    for (Class owner=receiver;owner;owner=class_getSuperclass(owner)) {
        unsigned count=0; Method *methods=class_copyMethodList(owner,&count);
        BOOL present=NO;
        for (unsigned i=0;i<count;i++) if (method_getName(methods[i])==selector) { present=YES; break; }
        free(methods);
        if (present) return;
    }
    /* Atomic add-only: a competing own-class implementation wins unchanged. */
    class_addMethod(receiver,selector,imp,encoding);
}
