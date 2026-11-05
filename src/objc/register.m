/* No AppKit messages, framework loading or dynamic method resolution here.
 * AppKit must already be strongly linked; metadata policy is checked by consumers. */
#import "workspace-private.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include "providers-generated.h"
__attribute__((noinline)) void __recaulk_objc_register_workspace_class(Class receiver) {
    if (!receiver) return;
    SEL selector=sel_registerName(RECAULK_WORKSPACE_SELECTOR);
    for (Class owner=receiver;owner;owner=class_getSuperclass(owner)) {
        unsigned count=0; Method *methods=class_copyMethodList(owner,&count);
        BOOL present=NO;
        for (unsigned i=0;i<count;i++) if (method_getName(methods[i])==selector) { present=YES; break; }
        free(methods);
        if (present) return;
    }
    /* Atomic add-only: a competing own-class implementation wins unchanged. */
    class_addMethod(receiver,selector,(IMP)__recaulk_objc_workspace_open_urls,RECAULK_WORKSPACE_ENCODING);
}
void __recaulk_objc_activate(void) {
    __recaulk_objc_register_workspace_class(objc_getClass(RECAULK_WORKSPACE_CLASS));
}
__attribute__((constructor)) static void activateAtLoad(void) { __recaulk_objc_activate(); }
