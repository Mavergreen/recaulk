/* spec: README.md "Dispatch on 10.9" -- the 10.10 to 10.12 dispatch calls Swift's Dispatch overlay makes, each case
   one run: tests/dispatch-modern-test.sh says which return and which trap. Compiled against Recaulk's headers,
   so the declarations are the ones a client sees. */
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static dispatch_queue_t q1, q2, inner;

static void *not_on_pthread(void *queue) { dispatch_assert_queue_not(queue); return NULL; }
static void *barrier_on_pthread(void *queue) { dispatch_assert_queue_barrier(queue); return NULL; }
static void on_pthread(void *(*f)(void *), dispatch_queue_t queue) {
    pthread_t t;
    pthread_create(&t, NULL, f, queue);
    pthread_join(t, NULL);
}

static int global_qos(void) {
    static const struct { long qos, priority; } map[] = {
        { QOS_CLASS_USER_INTERACTIVE, DISPATCH_QUEUE_PRIORITY_HIGH },
        { QOS_CLASS_USER_INITIATED, DISPATCH_QUEUE_PRIORITY_HIGH },
        { QOS_CLASS_DEFAULT, DISPATCH_QUEUE_PRIORITY_DEFAULT },
        { QOS_CLASS_UTILITY, DISPATCH_QUEUE_PRIORITY_LOW },
        { QOS_CLASS_BACKGROUND, DISPATCH_QUEUE_PRIORITY_BACKGROUND },
        { QOS_CLASS_UNSPECIFIED, DISPATCH_QUEUE_PRIORITY_DEFAULT },
    };
    int bad = 0;
    for (size_t i = 0; i < sizeof map / sizeof *map; i++) {
        dispatch_queue_t got = dispatch_get_global_queue(map[i].qos, 0);
        dispatch_queue_t want = dispatch_get_global_queue(map[i].priority, 0);
        if (!got || got != want) {
            printf("FAIL: dispatch_get_global_queue(%#lx) is %p, not the priority %ld queue %p\n",
                   map[i].qos, (void *)got, map[i].priority, (void *)want);
            bad = 1;
        }
    }
    return bad;
}

/* Two blocks that each wait for the other finish only on a concurrent queue. */
static int runs_concurrently(dispatch_queue_t q) {
    dispatch_semaphore_t a = dispatch_semaphore_create(0), b = dispatch_semaphore_create(0);
    dispatch_group_t g = dispatch_group_create();
    __block long ta = 1, tb = 1;
    dispatch_group_async(g, q, ^{ dispatch_semaphore_signal(a); tb = dispatch_semaphore_wait(b, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)); });
    dispatch_group_async(g, q, ^{ dispatch_semaphore_signal(b); ta = dispatch_semaphore_wait(a, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)); });
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
    return ta == 0 && tb == 0;
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s CASE\n", argv[0]); return 2; }
    const char *c = argv[1];
    q1 = dispatch_queue_create("recaulk.q1", DISPATCH_QUEUE_SERIAL);
    q2 = dispatch_queue_create("recaulk.q2", DISPATCH_QUEUE_SERIAL);
    inner = dispatch_queue_create("recaulk.inner", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(inner, q1);

    if (!strcmp(c, "global-qos")) return global_qos();
    if (!strcmp(c, "queue-qos-class")) {
        int rp = 7;
        dispatch_qos_class_t k = dispatch_queue_get_qos_class(q1, &rp);
        if (k != QOS_CLASS_UNSPECIFIED || rp != 0) { printf("FAIL: qos class %#x, relative priority %d\n", k, rp); return 1; }
        return dispatch_queue_get_qos_class(q1, NULL) != QOS_CLASS_UNSPECIFIED;
    }
    if (!strcmp(c, "autorelease-frequency")) {
        dispatch_queue_attr_t a = dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_CONCURRENT,
            DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM);
        if (!runs_concurrently(dispatch_queue_create("recaulk.arf", a))) { puts("FAIL: the concurrent attribute was lost"); return 1; }
        return 0;
    }
    if (!strcmp(c, "create-with-target")) {
        dispatch_queue_t t = dispatch_queue_create_with_target("recaulk.cwt", DISPATCH_QUEUE_SERIAL, q1);
        __block int ran = 0;
        dispatch_sync(t, ^{ ran = 1; });
        return !ran;
    }
    if (!strcmp(c, "assert-in-sync")) { dispatch_sync(q1, ^{ dispatch_assert_queue(q1); }); return 0; }
    if (!strcmp(c, "not-off-on-pthread")) { on_pthread(not_on_pthread, q1); return 0; }
    if (!strcmp(c, "not-other-queue-block")) { dispatch_sync(q2, ^{ dispatch_assert_queue_not(q1); }); return 0; }
    if (!strcmp(c, "not-in-sync")) { dispatch_sync(q1, ^{ dispatch_assert_queue_not(q1); }); return 0; }
    if (!strcmp(c, "not-target-in-block")) { dispatch_sync(inner, ^{ dispatch_assert_queue_not(q1); }); return 0; }
    if (!strcmp(c, "not-main-on-main-thread")) { dispatch_assert_queue_not(dispatch_get_main_queue()); return 0; }
    if (!strcmp(c, "not-null")) { dispatch_assert_queue_not(NULL); return 0; }
    if (!strcmp(c, "barrier-in-sync")) { dispatch_sync(q1, ^{ dispatch_assert_queue_barrier(q1); }); return 0; }
    if (!strcmp(c, "barrier-off-on-pthread")) { on_pthread(barrier_on_pthread, q1); return 0; }
    fprintf(stderr, "unknown case %s\n", c);
    return 2;
}
