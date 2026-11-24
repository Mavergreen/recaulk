/* +[NSGraphicsContext graphicsContextWithCGContext:flipped:] (10.10), a schema-2 group of one behind its own root,
 * ___recaulk_objc_activate_graphics_context. 10.9's graphicsContextWithGraphicsPort:flipped: takes the same
 * CGContextRef as a void *. The root registers with the runtime's C API only, in the one shape Drydock's verifier
 * follows (README.md "Objective-C methods"): a literal name, looked up before it is added. */
#import "workspace-private.h"
#import <objc/runtime.h>
#include "providers-generated.h"

NSGraphicsContext *__recaulk_objc_graphics_context_with_cgcontext(Class self, SEL _cmd, CGContextRef port, BOOL flipped) {
    (void)self;
    (void)_cmd;
    return [NSGraphicsContext graphicsContextWithGraphicsPort:port flipped:flipped];
}

__attribute__((noinline)) void __recaulk_objc_activate_graphics_context(void) {
    Class cls = objc_getClass(RECAULK_GRAPHICS_CONTEXT_CGCONTEXT_CLASS);
    if (!cls) return;
    SEL wrap = sel_registerName(RECAULK_GRAPHICS_CONTEXT_CGCONTEXT_SELECTOR);
    if (class_getClassMethod(cls, wrap)) return;
    class_addMethod(object_getClass(cls), wrap, (IMP)__recaulk_objc_graphics_context_with_cgcontext,
                    RECAULK_GRAPHICS_CONTEXT_CGCONTEXT_ENCODING);
    /* Not a tail call: Drydock 0.7.0's executor loses the failed-add path of a class_addMethod reached by a jump
       (regexec.c do_call: the fork keeps the jump's fall-through address), so the last add returns here. */
    __asm__ volatile("" ::: "memory");
}
__attribute__((constructor)) static void activateAtLoad(void) { __recaulk_objc_activate_graphics_context(); }
