/*
 * Copyright (c) 2025
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

/* spec: README.md "Swift's Dispatch" -- for Swift's importer only, the 11.3 SDK's OS_OBJECT_SWIFT3 classes: Dispatch's
   API notes make DispatchQueue and the rest from classes, and 10.9's headers declare protocol types. They must be
   declared through OS_OBJECT_DECL before the SDK's dispatch headers use it, so before the #include_next below.
   platform: measured on 10.9.5, its libdispatch registers each class with 11.3's superclass: OS_object : NSObject,
   OS_dispatch_object : OS_object, the rest : OS_dispatch_object, except OS_dispatch_data : NSObject. */
#ifdef __swift__
#include <os/object.h>
#if OS_OBJECT_USE_OBJC && !defined(OS_OBJECT_SWIFT3)
#define RECAULK_DISPATCH_SWIFT_CLASSES 1
#define __RECAULK_SWIFT_INIT_UNAVAILABLE \
    - (instancetype)init __attribute__((availability(swift, unavailable, message="Unavailable in Swift")));
__attribute__((objc_runtime_visible)) __attribute__((visibility("default")))
@interface OS_object : NSObject
__RECAULK_SWIFT_INIT_UNAVAILABLE
@end
#define __RECAULK_SWIFT_CLASS(name, super) \
    __attribute__((objc_runtime_visible)) __attribute__((visibility("default"))) \
    @interface OS_OBJECT_CLASS(name) : super \
    __RECAULK_SWIFT_INIT_UNAVAILABLE \
    @end \
    typedef OS_OBJECT_CLASS(name) *name##_t
/* OS_dispatch_data's superclass is NSObject: __RECAULK_SWIFT_SUPER(name, default) picks it by name. */
#define __RECAULK_SWIFT_SECOND(a, b, ...) b
#define __RECAULK_SWIFT_PICK(...) __RECAULK_SWIFT_SECOND(__VA_ARGS__)
#define __RECAULK_SWIFT_SUPER_dispatch_data ~, NSObject
#define __RECAULK_SWIFT_SUPER(name, dflt) __RECAULK_SWIFT_PICK(__RECAULK_SWIFT_SUPER_##name, dflt, ~)
/* spec: the 11.3 SDK's os/object.h -- OS_OBJECT_USE_OBJC_RETAIN_RELEASE is 0 under OS_OBJECT_SWIFT3, so
   dispatch_retain and dispatch_release stay functions. */
#undef OS_OBJECT_USE_OBJC_RETAIN_RELEASE
#define OS_OBJECT_USE_OBJC_RETAIN_RELEASE 0
#undef OS_OBJECT_DECL
#undef OS_OBJECT_DECL_SUBCLASS
#define OS_OBJECT_DECL(name, ...) __RECAULK_SWIFT_CLASS(name, OS_object)
#define OS_OBJECT_DECL_SUBCLASS(name, super) \
    __RECAULK_SWIFT_CLASS(name, __RECAULK_SWIFT_SUPER(name, OS_OBJECT_CLASS(super)))
#endif
#endif

/* Include the primary system dispatch/dispatch.h */
#include_next <dispatch/dispatch.h>

#ifndef RECAULK_DISPATCH_H
#define RECAULK_DISPATCH_H
#include <pthread/qos.h>

/* spec: the 11.3 SDK's dispatch/object.h, queue.h, block.h and workloop.h declare these; Recaulk defines
   them (README.md "Declarations"). 10.9 has no quality-of-service classes or workloops: the classes are
   accepted and dropped, and a workloop is a serial queue. */
#include <sys/cdefs.h>
__BEGIN_DECLS
/* spec: README.md "Fixes to functions 10.9 has" -- a program built from source gets a global queue for a QoS class,
   an inactive queue for an initially inactive attribute, and a resume that
   counts as an activation, whatever its link order (a -lc ahead of
   librecaulk.a names libSystem, whose copies return NULL for a class and an active queue, and leave a later
   dispatch_activate to over-resume). An asm
   label, not a macro, so Swift's importer still sees dispatch_get_global_queue; its type is the SDK's own. Not inside Recaulk, whose own
   sources define the 10.9 name. */
#ifndef __RECAULK_SOURCE__
__typeof__(dispatch_get_global_queue) dispatch_get_global_queue __asm("___recaulk_dispatch_get_global_queue");
__typeof__(dispatch_queue_create) dispatch_queue_create __asm("___recaulk_dispatch_queue_create");
__typeof__(dispatch_resume) dispatch_resume __asm("___recaulk_dispatch_resume");
#endif
/* spec: README.md "Declarations" -- each group only where the SDK in use lacks it, so a newer SDK
   compiles through this wrapper: QoS and dispatch blocks are 10.10, dispatch_activate 10.12,
   the and_wait calls and workloops 10.14. */
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101000
typedef qos_class_t dispatch_qos_class_t;
dispatch_qos_class_t dispatch_queue_get_qos_class(dispatch_queue_t queue, int *relative_priority_ptr);
void dispatch_set_qos_class_floor(dispatch_object_t object, dispatch_qos_class_t qos_class, int relative_priority);
dispatch_queue_attr_t dispatch_queue_attr_make_with_qos_class(dispatch_queue_attr_t attr,
    dispatch_qos_class_t qos_class, int relative_priority);
#ifdef __BLOCKS__
/* spec: the 11.3 SDK's DISPATCH_OPTIONS -- a fixed, flag enum, so Swift imports the flags as an OptionSet */
#if __has_feature(objc_fixed_enum)
typedef enum : unsigned long {
#else
enum {
#endif
    DISPATCH_BLOCK_BARRIER = 0x1ul,
    DISPATCH_BLOCK_DETACHED = 0x2ul,
    DISPATCH_BLOCK_ASSIGN_CURRENT = 0x4ul,
    DISPATCH_BLOCK_NO_QOS_CLASS = 0x8ul,
    DISPATCH_BLOCK_INHERIT_QOS_CLASS = 0x10ul,
    DISPATCH_BLOCK_ENFORCE_QOS_CLASS = 0x20ul,
#if __has_feature(objc_fixed_enum)
} __attribute__((flag_enum)) dispatch_block_flags_t;
#else
};
typedef unsigned long dispatch_block_flags_t;
#endif
dispatch_block_t dispatch_block_create(dispatch_block_flags_t flags, dispatch_block_t block);
dispatch_block_t dispatch_block_create_with_qos_class(dispatch_block_flags_t flags,
    dispatch_qos_class_t qos_class, int relative_priority, dispatch_block_t block);
void dispatch_block_cancel(dispatch_block_t block);
intptr_t dispatch_block_testcancel(dispatch_block_t block);
intptr_t dispatch_block_wait(dispatch_block_t block, dispatch_time_t timeout);
void dispatch_block_notify(dispatch_block_t block, dispatch_queue_t queue, dispatch_block_t notification_block);
#endif
#endif
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101200
/* dispatch_activate starts a queue made inactive, and a source, once; any other object it leaves alone. */
void dispatch_activate(dispatch_object_t object);
dispatch_queue_attr_t dispatch_queue_attr_make_initially_inactive(dispatch_queue_attr_t attr);
/* spec: the 11.3 SDK's queue.h, with its DISPATCH_ALIAS_V2 labels: the $V2 names are the ones Recaulk defines */
dispatch_queue_t dispatch_queue_create_with_target(const char *label, dispatch_queue_attr_t attr,
    dispatch_queue_t target) __asm__("_dispatch_queue_create_with_target$V2");
void dispatch_assert_queue(dispatch_queue_t queue) __asm__("_dispatch_assert_queue$V2");
void dispatch_assert_queue_barrier(dispatch_queue_t queue);
void dispatch_assert_queue_not(dispatch_queue_t queue) __asm__("_dispatch_assert_queue_not$V2");
#if __has_feature(objc_fixed_enum)
typedef enum : unsigned long {
#else
enum {
#endif
    DISPATCH_AUTORELEASE_FREQUENCY_INHERIT = 0,
    DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM = 1,
    DISPATCH_AUTORELEASE_FREQUENCY_NEVER = 2,
#if __has_feature(objc_fixed_enum)
} dispatch_autorelease_frequency_t;
#else
};
typedef unsigned long dispatch_autorelease_frequency_t;
#endif
dispatch_queue_attr_t dispatch_queue_attr_make_with_autorelease_frequency(dispatch_queue_attr_t attr,
    dispatch_autorelease_frequency_t frequency);
#endif
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101400
void dispatch_async_and_wait_f(dispatch_queue_t queue, void *context, dispatch_function_t work);
void dispatch_barrier_async_and_wait_f(dispatch_queue_t queue, void *context, dispatch_function_t work);
/* platform: DISPATCH_DECL_SUBCLASS(dispatch_workloop, dispatch_queue) in the 11.3 SDK; 10.9's dispatch
   has no subclass macro, and a workloop is a queue wherever one is accepted. */
typedef dispatch_queue_t dispatch_workloop_t;
dispatch_workloop_t dispatch_workloop_create(const char *label);
dispatch_workloop_t dispatch_workloop_create_inactive(const char *label);
#ifdef __BLOCKS__
void dispatch_async_and_wait(dispatch_queue_t queue, dispatch_block_t block);
void dispatch_barrier_async_and_wait(dispatch_queue_t queue, dispatch_block_t block);
#endif
#endif
__END_DECLS
#endif
#ifdef RECAULK_DISPATCH_SWIFT_CLASSES
#ifndef RECAULK_DISPATCH_SWIFT_SOURCES
#define RECAULK_DISPATCH_SWIFT_SOURCES
/* spec: the 11.3 SDK's DISPATCH_SOURCE_DECL and DISPATCH_SOURCE_TYPE_DECL -- the protocols the source class adopts,
   one per source type. platform: 10.9's runtime has none of them, so in Swift a static upcast to
   DispatchSourceTimer and the rest works but a dynamic `as?` fails. */
@protocol OS_dispatch_source <NSObject>
@end
@interface OS_dispatch_source () <OS_dispatch_source>
@end
#define __RECAULK_SWIFT_SOURCE(t) \
    @protocol OS_dispatch_source_##t <OS_dispatch_source> \
    @end \
    @interface OS_dispatch_source () <OS_dispatch_source_##t> \
    @end
__RECAULK_SWIFT_SOURCE(data_add) __RECAULK_SWIFT_SOURCE(data_or) __RECAULK_SWIFT_SOURCE(mach_send)
__RECAULK_SWIFT_SOURCE(mach_recv) __RECAULK_SWIFT_SOURCE(memorypressure) __RECAULK_SWIFT_SOURCE(proc)
__RECAULK_SWIFT_SOURCE(read) __RECAULK_SWIFT_SOURCE(signal) __RECAULK_SWIFT_SOURCE(timer)
__RECAULK_SWIFT_SOURCE(vnode) __RECAULK_SWIFT_SOURCE(write)
#endif
#endif
