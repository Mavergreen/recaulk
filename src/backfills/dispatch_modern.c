/*
 * libdispatch entry points added after 10.9.
 *
 * Two of these are real implementations; the rest report the absence of a
 * facility 10.9 genuinely does not have, in the same terms the real API uses
 * for "nothing here".
 */

#include <dispatch/dispatch.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Block.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "MacportsLegacySupport.h"

/* dispatch_block_create returns a block carrying its state: cancelled, finished, and who waits on it. The
 * state has to travel with the block itself, because dispatch_block_cancel, _wait and _notify are handed only
 * the block, so it is attached as an associated object -- a block is an Objective-C object, so this works on
 * 10.9. A cancelled block that has not yet begun does nothing when it runs, and still finishes then.
 *
 * Every copy of Recaulk in a process shares the state: a program's own and the hidden subset a library such
 * as libswiftDispatch links. So the association key is a selector, which the runtime makes one pointer per
 * name process-wide, and the state's layout is fixed by the version in that name: a layout change takes a
 * new name. A copy without it (Recaulk before 20261120) keys on an address of its own and sees only its own
 * blocks. */
#define RECAULK_BLOCK_STATE_KEY "__recaulk_dispatch_block_state_v1"
#define RECAULK_BLOCK_STATE_MAGIC 0x52434231u /* 'RCB1' */

struct block_waiter {
    struct block_waiter *next;
    dispatch_semaphore_t wake;          /* a dispatch_block_wait, or NULL for a notify */
    dispatch_queue_t queue;             /* a dispatch_block_notify's queue and block */
    dispatch_block_t notification;
};

struct block_state {                    /* layout v1: every copy of Recaulk agrees on it */
    uint32_t magic;
    volatile int cancelled;
    int finished;
    pthread_mutex_t lock;
    struct block_waiter *waiters;
};

static const void *state_key(void) {
    static SEL key;
    SEL k = __atomic_load_n(&key, __ATOMIC_ACQUIRE);
    if (!k) { k = sel_registerName(RECAULK_BLOCK_STATE_KEY); __atomic_store_n(&key, k, __ATOMIC_RELEASE); }
    return (const void *)k;
}

static void drop_waiter(struct block_waiter *w) {
    if (w->queue) dispatch_release(w->queue);
    if (w->notification) Block_release(w->notification);
    free(w);
}

/* The state lives in CFData bytes whose deallocator releases what a block released unrun still holds: its
 * notifications never run, as libdispatch's never do for a block that never runs. */
static void state_deallocate(void *ptr, void *info) {
    (void)info;
    struct block_state *st = ptr;
    struct block_waiter *w = st->waiters;
    while (w) { struct block_waiter *next = w->next; drop_waiter(w); w = next; }
    pthread_mutex_destroy(&st->lock);
    free(st);
}
static void *state_allocate(CFIndex size, CFOptionFlags hint, void *info) {
    (void)hint; (void)info;
    return malloc((size_t)size);
}
static CFAllocatorRef state_allocator(void) {
    static CFAllocatorRef allocator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFAllocatorContext context = { 0, NULL, NULL, NULL, NULL, state_allocate, NULL, state_deallocate, NULL };
        allocator = CFAllocatorCreate(kCFAllocatorDefault, &context);
    });
    return allocator;
}

static struct block_state *state_for(dispatch_block_t block) {
    if (!block) return NULL;
    CFDataRef holder = (CFDataRef)objc_getAssociatedObject((id)block, state_key());
    if (!holder || CFGetTypeID(holder) != CFDataGetTypeID() || CFDataGetLength(holder) != sizeof(struct block_state))
        return NULL;
    struct block_state *st = (struct block_state *)CFDataGetBytePtr(holder);
    return st->magic == RECAULK_BLOCK_STATE_MAGIC ? st : NULL;
}

/* A block finishes once: the waiters are woken and the notifications submitted. libdispatch traps on a
 * second run; this ignores it. */
static void finish(struct block_state *st) {
    pthread_mutex_lock(&st->lock);
    if (st->finished) { pthread_mutex_unlock(&st->lock); return; }
    st->finished = 1;
    struct block_waiter *w = st->waiters;
    st->waiters = NULL;
    pthread_mutex_unlock(&st->lock);
    while (w) {
        struct block_waiter *next = w->next;
        if (w->wake) { dispatch_semaphore_signal(w->wake); free(w); }
        else { dispatch_async(w->queue, w->notification); drop_waiter(w); }
        w = next;
    }
}

dispatch_block_t dispatch_block_create(dispatch_block_flags_t flags, dispatch_block_t block) {
    (void)flags;
    if (!block) return NULL;
    struct block_state *st = calloc(1, sizeof *st);
    if (!st) return NULL;
    st->magic = RECAULK_BLOCK_STATE_MAGIC;
    pthread_mutex_init(&st->lock, NULL);
    CFDataRef holder = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, (const UInt8 *)st, sizeof *st, state_allocator());
    if (!holder) { pthread_mutex_destroy(&st->lock); free(st); return NULL; }

    dispatch_block_t inner = Block_copy(block);
    dispatch_block_t wrapper = Block_copy(^{
        if (!st->cancelled) inner();
        finish(st);
    });
    Block_release(inner);
    objc_setAssociatedObject((id)wrapper, state_key(), (id)holder, OBJC_ASSOCIATION_RETAIN);
    CFRelease(holder);
    return wrapper;
}

void dispatch_block_cancel(dispatch_block_t block) {
    struct block_state *st = state_for(block);
    if (st) __sync_lock_test_and_set(&st->cancelled, 1);
}

intptr_t dispatch_block_testcancel(dispatch_block_t block) {
    struct block_state *st = state_for(block);
    return st && st->cancelled ? 1 : 0;
}

__attribute__((noreturn)) static void invalid_block(const char *function) {
    char msg[160];
    int n = snprintf(msg, sizeof msg, "BUG IN CLIENT OF LIBDISPATCH: Invalid block object passed to %s()\n", function);
    if (n > 0) (void)write(STDERR_FILENO, msg, (size_t)n < sizeof msg ? (size_t)n : sizeof msg - 1);
    __builtin_trap();
}

/* dispatch_block_wait (10.10): 0 once the block has finished, non-zero when the timeout passes first. */
intptr_t dispatch_block_wait(dispatch_block_t block, dispatch_time_t timeout) {
    struct block_state *st = state_for(block);
    if (!st) invalid_block("dispatch_block_wait");
    struct block_waiter *w = calloc(1, sizeof *w);
    if (!w) return -1;
    pthread_mutex_lock(&st->lock);
    if (st->finished) { pthread_mutex_unlock(&st->lock); free(w); return 0; }
    dispatch_semaphore_t wake = w->wake = dispatch_semaphore_create(0);
    w->next = st->waiters;
    st->waiters = w;
    pthread_mutex_unlock(&st->lock);
    if (dispatch_semaphore_wait(wake, timeout) == 0) { dispatch_release(wake); return 0; }
    /* Timed out: take the waiter back, unless finish already has it, in which case its signal is coming. */
    pthread_mutex_lock(&st->lock);
    struct block_waiter **p = &st->waiters;
    while (*p && *p != w) p = &(*p)->next;
    int mine = *p == w;
    if (mine) *p = w->next;
    pthread_mutex_unlock(&st->lock);
    if (mine) { free(w); dispatch_release(wake); return -1; }
    dispatch_semaphore_wait(wake, DISPATCH_TIME_FOREVER);
    dispatch_release(wake);
    return 0;
}

/* dispatch_block_notify (10.10): submits notification_block to queue once the block has finished, at once if
 * it already has. */
void dispatch_block_notify(dispatch_block_t block, dispatch_queue_t queue, dispatch_block_t notification_block) {
    struct block_state *st = state_for(block);
    if (!st) invalid_block("dispatch_block_notify");
    struct block_waiter *w = calloc(1, sizeof *w);
    if (!w) return;
    dispatch_retain(queue);
    w->queue = queue;
    w->notification = Block_copy(notification_block);
    pthread_mutex_lock(&st->lock);
    if (!st->finished) { w->next = st->waiters; st->waiters = w; w = NULL; }
    pthread_mutex_unlock(&st->lock);
    if (w) { dispatch_async(w->queue, w->notification); drop_waiter(w); }
}

/* The QoS-taking form of dispatch_block_create (10.10). 10.9 has no
 * quality-of-service classes, so the class and relative priority are dropped;
 * what the caller actually depends on -- a block it can cancel -- is
 * unaffected, and scheduling falls back to the single priority this OS has. */
dispatch_block_t dispatch_block_create_with_qos_class(dispatch_block_flags_t flags,
                                                      dispatch_qos_class_t qos_class,
                                                      int relative_priority,
                                                      dispatch_block_t block) {
    (void)qos_class;
    (void)relative_priority;
    return dispatch_block_create(flags, block);
}

/* 10.9 has no quality-of-service classes. Returning the attribute unchanged
 * keeps the queue's serial/concurrent nature, which is the part that affects
 * correctness; only the scheduling hint is lost. */
dispatch_queue_attr_t
dispatch_queue_attr_make_with_qos_class(dispatch_queue_attr_t attr,
                                        dispatch_qos_class_t qos_class, int relative_priority) {
    (void)qos_class;
    (void)relative_priority;
    return attr;
}

/* dispatch_queue_get_qos_class (10.10): 10.9's queues have no QoS class, so every queue reports
 * QOS_CLASS_UNSPECIFIED and a relative priority of 0, as Recaulk's pthread QoS calls answer. */
dispatch_qos_class_t dispatch_queue_get_qos_class(dispatch_queue_t queue, int *relative_priority_ptr) {
    (void)queue;
    if (relative_priority_ptr) *relative_priority_ptr = 0;
    return QOS_CLASS_UNSPECIFIED;
}

/* dispatch_queue_attr_make_with_autorelease_frequency (10.12): 10.9's queues drain no autorelease pool of
 * their own, so the frequency is dropped and the attribute keeps its serial or concurrent nature. */
dispatch_queue_attr_t dispatch_queue_attr_make_with_autorelease_frequency(dispatch_queue_attr_t attr,
                                                                          dispatch_autorelease_frequency_t frequency) {
    (void)frequency;
    return attr;
}

/* Vouchers (activity tracing identities) do not exist on 10.9. The real API
 * returns NULL for "no voucher", and adopting NULL yields the previous
 * voucher, which is also NULL. */
void *voucher_copy(void) {
    return NULL;
}

void *voucher_adopt(void *voucher) {
    (void)voucher;
    return NULL;
}

/* os_release is os_object_release. With OS_OBJECT_USE_OBJC these are ordinary
 * Objective-C objects, so the release message is the real operation. */
void os_release(void *object) {
    if (!object) return;
    ((void (*)(id, SEL))objc_msgSend)((id)object, sel_registerName("release"));
}
