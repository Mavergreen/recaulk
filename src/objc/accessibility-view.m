/* 10.10's NSAccessibility properties on NSView (label, role, children, selected text range, and -accessibilityFrame),
 * as one schema-2 group behind its own root, ___recaulk_objc_activate_view_accessibility. A control's properties live
 * on its cell, the element 10.9 exposes (accessibility-common.m). The root registers with the runtime's C API only, in
 * the one shape Drydock's verifier follows (README.md "Objective-C methods"): literal names, every member looked up
 * before any is added. */
#import "workspace-private.h"
#import <objc/runtime.h>
#include "providers-generated.h"

void __recaulk_objc_view_set_accessibility_label(NSView *self, SEL _cmd, NSString *label) {
    (void)_cmd;
    __recaulk_objc_ax_view_set(self, label, NSAccessibilityDescriptionAttribute);
}
NSString *__recaulk_objc_view_accessibility_label(NSView *self, SEL _cmd) {
    (void)_cmd;
    return __recaulk_objc_ax_view_value(self, NSAccessibilityDescriptionAttribute);
}
void __recaulk_objc_view_set_accessibility_role(NSView *self, SEL _cmd, NSString *role) {
    (void)_cmd;
    __recaulk_objc_ax_view_set(self, role, NSAccessibilityRoleAttribute);
}
NSString *__recaulk_objc_view_accessibility_role(NSView *self, SEL _cmd) {
    (void)_cmd;
    return __recaulk_objc_ax_view_value(self, NSAccessibilityRoleAttribute);
}
void __recaulk_objc_view_set_accessibility_children(NSView *self, SEL _cmd, NSArray *children) {
    (void)_cmd;
    __recaulk_objc_ax_view_set(self, children, NSAccessibilityChildrenAttribute);
}
NSArray *__recaulk_objc_view_accessibility_children(NSView *self, SEL _cmd) {
    (void)_cmd;
    return __recaulk_objc_ax_view_value(self, NSAccessibilityChildrenAttribute);
}
void __recaulk_objc_view_set_accessibility_selected_text_range(NSView *self, SEL _cmd, NSRange range) {
    (void)_cmd;
    __recaulk_objc_ax_view_set(self, [NSValue valueWithRange:range], NSAccessibilitySelectedTextRangeAttribute);
}
NSRange __recaulk_objc_view_accessibility_selected_text_range(NSView *self, SEL _cmd) {
    (void)_cmd;
    return __recaulk_objc_ax_range(__recaulk_objc_ax_view_value(self, NSAccessibilitySelectedTextRangeAttribute));
}
NSRect __recaulk_objc_view_accessibility_frame(NSView *self, SEL _cmd) {
    (void)_cmd;
    return __recaulk_objc_ax_frame(__recaulk_objc_ax_view_value(self, NSAccessibilityPositionAttribute),
                                  __recaulk_objc_ax_view_value(self, NSAccessibilitySizeAttribute));
}

__attribute__((noinline)) void __recaulk_objc_activate_view_accessibility(void) {
    Class cls = objc_getClass(RECAULK_VIEW_SET_AX_LABEL_CLASS);
    if (!cls) return;
    SEL setLabel = sel_registerName(RECAULK_VIEW_SET_AX_LABEL_SELECTOR);
    SEL label = sel_registerName(RECAULK_VIEW_AX_LABEL_SELECTOR);
    SEL setRole = sel_registerName(RECAULK_VIEW_SET_AX_ROLE_SELECTOR);
    SEL role = sel_registerName(RECAULK_VIEW_AX_ROLE_SELECTOR);
    SEL setChildren = sel_registerName(RECAULK_VIEW_SET_AX_CHILDREN_SELECTOR);
    SEL children = sel_registerName(RECAULK_VIEW_AX_CHILDREN_SELECTOR);
    SEL setRange = sel_registerName(RECAULK_VIEW_SET_AX_SELECTED_TEXT_RANGE_SELECTOR);
    SEL range = sel_registerName(RECAULK_VIEW_AX_SELECTED_TEXT_RANGE_SELECTOR);
    SEL frame = sel_registerName(RECAULK_VIEW_AX_FRAME_SELECTOR);
    if (class_getInstanceMethod(cls, setLabel) || class_getInstanceMethod(cls, label) ||
        class_getInstanceMethod(cls, setRole) || class_getInstanceMethod(cls, role) ||
        class_getInstanceMethod(cls, setChildren) || class_getInstanceMethod(cls, children) ||
        class_getInstanceMethod(cls, setRange) || class_getInstanceMethod(cls, range) ||
        class_getInstanceMethod(cls, frame))
        return;
    class_addMethod(cls, setLabel, (IMP)__recaulk_objc_view_set_accessibility_label,
                    RECAULK_VIEW_SET_AX_LABEL_ENCODING);
    class_addMethod(cls, label, (IMP)__recaulk_objc_view_accessibility_label, RECAULK_VIEW_AX_LABEL_ENCODING);
    class_addMethod(cls, setRole, (IMP)__recaulk_objc_view_set_accessibility_role, RECAULK_VIEW_SET_AX_ROLE_ENCODING);
    class_addMethod(cls, role, (IMP)__recaulk_objc_view_accessibility_role, RECAULK_VIEW_AX_ROLE_ENCODING);
    class_addMethod(cls, setChildren, (IMP)__recaulk_objc_view_set_accessibility_children,
                    RECAULK_VIEW_SET_AX_CHILDREN_ENCODING);
    class_addMethod(cls, children, (IMP)__recaulk_objc_view_accessibility_children, RECAULK_VIEW_AX_CHILDREN_ENCODING);
    class_addMethod(cls, setRange, (IMP)__recaulk_objc_view_set_accessibility_selected_text_range,
                    RECAULK_VIEW_SET_AX_SELECTED_TEXT_RANGE_ENCODING);
    class_addMethod(cls, range, (IMP)__recaulk_objc_view_accessibility_selected_text_range,
                    RECAULK_VIEW_AX_SELECTED_TEXT_RANGE_ENCODING);
    class_addMethod(cls, frame, (IMP)__recaulk_objc_view_accessibility_frame, RECAULK_VIEW_AX_FRAME_ENCODING);
    /* Not a tail call: Drydock 0.7.0's executor loses the failed-add path of a class_addMethod reached by a jump
       (regexec.c do_call: the fork keeps the jump's fall-through address), so the last add returns here. */
    __asm__ volatile("" ::: "memory");
}

__attribute__((constructor)) static void activateAtLoad(void) { __recaulk_objc_activate_view_accessibility(); }
