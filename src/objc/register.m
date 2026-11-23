/* No AppKit messages, framework loading or dynamic method resolution here.
 * AppKit must already be strongly linked; metadata policy is checked by consumers. */
#import "workspace-private.h"
#import "register-common.h"
#include "providers-generated.h"
__attribute__((noinline)) void __recaulk_objc_register_workspace_class(Class receiver) {
    __recaulk_objc_add_method(receiver,sel_registerName(RECAULK_WORKSPACE_SELECTOR),(IMP)__recaulk_objc_workspace_open_urls,RECAULK_WORKSPACE_ENCODING);
    __recaulk_objc_add_method(receiver,sel_registerName(RECAULK_WORKSPACE_VOICEOVER_SELECTOR),(IMP)__recaulk_objc_workspace_is_voiceover_enabled,
        RECAULK_WORKSPACE_VOICEOVER_ENCODING);
    __recaulk_objc_add_method(receiver,sel_registerName(RECAULK_WORKSPACE_REDUCE_MOTION_SELECTOR),
        (IMP)__recaulk_objc_workspace_should_reduce_motion,RECAULK_WORKSPACE_REDUCE_MOTION_ENCODING);
}
__attribute__((noinline)) void __recaulk_objc_register_control_class(Class receiver) {
    __recaulk_objc_add_method(receiver,sel_registerName(RECAULK_CONTROL_SINGLE_LINE_SELECTOR),
        (IMP)__recaulk_objc_control_uses_single_line_mode,RECAULK_CONTROL_SINGLE_LINE_ENCODING);
    __recaulk_objc_add_method(receiver,sel_registerName(RECAULK_CONTROL_SET_SINGLE_LINE_SELECTOR),
        (IMP)__recaulk_objc_control_set_uses_single_line_mode,RECAULK_CONTROL_SET_SINGLE_LINE_ENCODING);
}
void __recaulk_objc_activate(void) {
    __recaulk_objc_register_workspace_class(objc_getClass(RECAULK_WORKSPACE_CLASS));
    __recaulk_objc_register_control_class(objc_getClass(RECAULK_CONTROL_SINGLE_LINE_CLASS));
}
__attribute__((constructor)) static void activateAtLoad(void) { __recaulk_objc_activate(); }
