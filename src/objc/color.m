/* +[NSColor labelColor] and +linkColor (10.10), as one schema-2 group behind its own root,
 * ___recaulk_objc_activate_color. 10.9 draws a label in controlTextColor, so labelColor is that; linkColor is the
 * blue 10.10 draws links in, in sRGB. The root registers with the runtime's C API only, in the one shape Drydock's
 * verifier follows (README.md "Objective-C methods"): literal names, every member looked up before any is added. */
#import "workspace-private.h"
#import <objc/runtime.h>
#include "providers-generated.h"

NSColor *__recaulk_objc_color_label(Class self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return [NSColor controlTextColor];
}
NSColor *__recaulk_objc_color_link(Class self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return [NSColor colorWithSRGBRed:0.0 green:0.408 blue:0.855 alpha:1.0];
}

__attribute__((noinline)) void __recaulk_objc_activate_color(void) {
    Class cls = objc_getClass(RECAULK_COLOR_LABEL_CLASS);
    if (!cls) return;
    SEL label = sel_registerName(RECAULK_COLOR_LABEL_SELECTOR);
    SEL link = sel_registerName(RECAULK_COLOR_LINK_SELECTOR);
    if (class_getClassMethod(cls, label) || class_getClassMethod(cls, link)) return;
    Class meta = object_getClass(cls);
    class_addMethod(meta, label, (IMP)__recaulk_objc_color_label, RECAULK_COLOR_LABEL_ENCODING);
    class_addMethod(meta, link, (IMP)__recaulk_objc_color_link, RECAULK_COLOR_LINK_ENCODING);
    /* Not a tail call: Drydock 0.7.0's executor loses the failed-add path of a class_addMethod reached by a jump
       (regexec.c do_call: the fork keeps the jump's fall-through address), so the last add returns here. */
    __asm__ volatile("" ::: "memory");
}
__attribute__((constructor)) static void activateAtLoad(void) { __recaulk_objc_activate_color(); }
