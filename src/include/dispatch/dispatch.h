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

/* Include the primary system dispatch/dispatch.h */
#include_next <dispatch/dispatch.h>

#ifndef RECAULK_DISPATCH_H
#define RECAULK_DISPATCH_H
#include <pthread/qos.h>

/* spec: the 11.3 SDK's dispatch/object.h, queue.h, block.h and workloop.h declare these; Recaulk defines
   them (README.md "Declarations"). 10.9 has no quality-of-service classes or workloops: the classes are
   accepted and dropped, and a workloop is a serial queue. */
__BEGIN_DECLS
typedef qos_class_t dispatch_qos_class_t;
/* dispatch_activate resumes the object: before 10.12 a dispatch_resume started an inactive one. */
void dispatch_activate(dispatch_object_t object);
void dispatch_set_qos_class_floor(dispatch_object_t object, dispatch_qos_class_t qos_class, int relative_priority);
dispatch_queue_attr_t dispatch_queue_attr_make_with_qos_class(dispatch_queue_attr_t attr,
    dispatch_qos_class_t qos_class, int relative_priority);
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
typedef unsigned long dispatch_block_flags_t;
enum {
    DISPATCH_BLOCK_BARRIER = 0x1ul,
    DISPATCH_BLOCK_DETACHED = 0x2ul,
    DISPATCH_BLOCK_ASSIGN_CURRENT = 0x4ul,
    DISPATCH_BLOCK_NO_QOS_CLASS = 0x8ul,
    DISPATCH_BLOCK_INHERIT_QOS_CLASS = 0x10ul,
    DISPATCH_BLOCK_ENFORCE_QOS_CLASS = 0x20ul,
};
dispatch_block_t dispatch_block_create(dispatch_block_flags_t flags, dispatch_block_t block);
dispatch_block_t dispatch_block_create_with_qos_class(dispatch_block_flags_t flags,
    dispatch_qos_class_t qos_class, int relative_priority, dispatch_block_t block);
void dispatch_block_cancel(dispatch_block_t block);
intptr_t dispatch_block_testcancel(dispatch_block_t block);
#endif
__END_DECLS
#endif
