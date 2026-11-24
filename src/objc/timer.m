/* +[NSTimer scheduledTimerWithTimeInterval:repeats:block:] and +timerWithTimeInterval:repeats:block: (10.12), as one
 * schema-2 group behind its own root, ___recaulk_objc_activate_timer. 10.9's CFRunLoopTimer is toll-free bridged to
 * NSTimer and takes a block (CFRunLoopTimerCreateWithHandler, 10.7), whose argument is the timer, as NSTimer's block's
 * is. Neither body sends a message. The root registers with the runtime's C API only, in the one shape Drydock's
 * verifier follows (README.md "Objective-C methods"): literal names, every member looked up before any is added. */
#import "foundation-private.h"
#import <objc/runtime.h>
#include "providers-generated.h"

static NSTimer *timer(NSTimeInterval interval, BOOL repeats, void (^block)(NSTimer *timer)) {
    /* NSTimer.h: an interval of 0 or less is taken as 0.0001 s */
    if (interval <= 0) interval = 0.0001;
    CFRunLoopTimerRef t = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval,
        repeats ? interval : 0, 0, 0, (void (^)(CFRunLoopTimerRef))block);
    return (NSTimer *)CFAutorelease(t);
}
NSTimer *__recaulk_objc_timer_with_interval_block(Class self, SEL _cmd, NSTimeInterval interval, BOOL repeats,
                                                  void (^block)(NSTimer *timer)) {
    (void)self;
    (void)_cmd;
    return timer(interval, repeats, block);
}
NSTimer *__recaulk_objc_timer_scheduled_with_interval_block(Class self, SEL _cmd, NSTimeInterval interval, BOOL repeats,
                                                            void (^block)(NSTimer *timer)) {
    (void)self;
    (void)_cmd;
    NSTimer *t = timer(interval, repeats, block);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), (CFRunLoopTimerRef)t, kCFRunLoopDefaultMode);
    return t;
}

__attribute__((noinline)) void __recaulk_objc_activate_timer(void) {
    Class cls = objc_getClass(RECAULK_TIMER_SCHEDULED_BLOCK_CLASS);
    if (!cls) return;
    SEL scheduled = sel_registerName(RECAULK_TIMER_SCHEDULED_BLOCK_SELECTOR);
    SEL plain = sel_registerName(RECAULK_TIMER_BLOCK_SELECTOR);
    if (class_getClassMethod(cls, scheduled) || class_getClassMethod(cls, plain)) return;
    Class meta = object_getClass(cls);
    class_addMethod(meta, scheduled, (IMP)__recaulk_objc_timer_scheduled_with_interval_block, RECAULK_TIMER_SCHEDULED_BLOCK_ENCODING);
    class_addMethod(meta, plain, (IMP)__recaulk_objc_timer_with_interval_block, RECAULK_TIMER_BLOCK_ENCODING);
    /* Not a tail call: Drydock 0.7.0's executor loses the failed-add path of a class_addMethod reached by a jump
       (regexec.c do_call: the fork keeps the jump's fall-through address), so the last add returns here. */
    __asm__ volatile("" ::: "memory");
}
__attribute__((constructor)) static void activateAtLoad(void) { __recaulk_objc_activate_timer(); }
