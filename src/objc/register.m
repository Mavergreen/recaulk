/* No AppKit messages, framework loading or dynamic method resolution here.
 * AppKit must already be strongly linked; metadata policy is checked by consumers. */
#import "workspace-private.h"
#import "register-common.h"
#include "providers-generated.h"
__attribute__((noinline)) void __recaulk_objc_register_workspace_class(Class receiver) {
    __recaulk_objc_add_method(receiver,RECAULK_WORKSPACE_SELECTOR,(IMP)__recaulk_objc_workspace_open_urls,RECAULK_WORKSPACE_ENCODING);
}
void __recaulk_objc_activate(void) {
    __recaulk_objc_register_workspace_class(objc_getClass(RECAULK_WORKSPACE_CLASS));
}
__attribute__((constructor)) static void activateAtLoad(void) { __recaulk_objc_activate(); }
