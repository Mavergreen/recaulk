/*
 * dispatch_assert_queue (10.12), which a modern SDK binds as dispatch_assert_queue$V2.
 *
 * 10.9's libdispatch shows a thread only the innermost queue it runs a block for, and that queue's
 * targets: the queue that called dispatch_sync or dispatch_apply is hidden behind the one called. So
 * this traps only where the thread is provably not on the queue, and returns where it cannot tell.
 * See README.md "Queue assertions".
 */

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

extern pthread_t pthread_main_thread_np(void);

static char no_block_marker;

static void tag(dispatch_queue_t queue, const void *key, void *value) {
    if (dispatch_queue_get_specific(queue, key) != value)
        dispatch_queue_set_specific(queue, key, value, NULL);
}

static int in_current_hierarchy(dispatch_queue_t queue) {
    const void *key = (const char *)queue + 1;
    tag(queue, key, queue);
    return dispatch_get_specific(key) == queue;
}

static int runs_no_block(void) {
    dispatch_queue_t fallback = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 2);
    if (dispatch_get_current_queue() != fallback) return 0;
    tag(fallback, &no_block_marker, &no_block_marker);
    return dispatch_get_specific(&no_block_marker) == NULL;
}

static int main_queue_bound_to_main_thread(void) {
    return pthread_kill(pthread_main_thread_np(), 0) == 0;
}

__attribute__((noreturn)) static void fail(dispatch_queue_t queue) {
    char msg[512];
    const char *label = queue ? dispatch_queue_get_label(queue) : NULL;
    int n = snprintf(msg, sizeof msg,
                     "BUG IN CLIENT OF LIBDISPATCH: Assertion failed: Block was expected to execute on queue [%s (%p)]\n",
                     label ? label : "", (void *)queue);
    if (n > 0) (void)write(STDERR_FILENO, msg, (size_t)n < sizeof msg ? (size_t)n : sizeof msg - 1);
    __builtin_trap();
}

void dispatch_assert_queue_V2(dispatch_queue_t queue) __asm__("_dispatch_assert_queue$V2");
void dispatch_assert_queue_V2(dispatch_queue_t queue) {
    if (queue == NULL) fail(queue);
    int main_queue = queue == dispatch_get_main_queue();
    if (main_queue && pthread_main_np()) return;
    if (in_current_hierarchy(queue)) return;
    if (runs_no_block() || (main_queue && main_queue_bound_to_main_thread())) fail(queue);
}
