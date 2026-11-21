/* spec: README.md "Dispatch on 10.9" -- the 10.10 to 10.12 dispatch calls Swift's Dispatch overlay makes, each case
   one run: tests/dispatch-modern-test.sh says which return and which trap. Compiled against Recaulk's headers,
   so the declarations are the ones a client sees. */
#include <dispatch/dispatch.h>
#include <objc/runtime.h>
#include <stdint.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* platform: libobjc's ARC entry points, which Swift calls on every dispatch_queue_attr_t it holds */
void *objc_retain(void *);
void objc_release(void *);

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

/* A block submitted to q runs within ms milliseconds. */
static int runs_within(dispatch_queue_t q, long ms) {
    dispatch_semaphore_t ran = dispatch_semaphore_create(0);
    dispatch_async(q, ^{ dispatch_semaphore_signal(ran); });
    return dispatch_semaphore_wait(ran, dispatch_time(DISPATCH_TIME_NOW, ms * (long)NSEC_PER_MSEC)) == 0;
}

/* Inactive until dispatch_activate: a block waits, then runs; a second activate changes nothing. */
static int starts_inactive(dispatch_queue_t q, const char *what) {
    __block volatile int ran = 0;
    dispatch_async(q, ^{ ran = 1; });
    usleep(200000);
    if (ran) { printf("FAIL: %s ran a block before dispatch_activate\n", what); return 1; }
    dispatch_activate(q);
    dispatch_activate(q);
    if (!runs_within(q, 2000) || !ran) { printf("FAIL: %s ran no block after dispatch_activate\n", what); return 1; }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s CASE\n", argv[0]); return 2; }
    const char *c = argv[1];
    q1 = dispatch_queue_create("recaulk.q1", DISPATCH_QUEUE_SERIAL);
    q2 = dispatch_queue_create("recaulk.q2", DISPATCH_QUEUE_SERIAL);
    inner = dispatch_queue_create("recaulk.inner", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(inner, q1);

    if (!strcmp(c, "global-qos")) return global_qos();
    if (!strcmp(c, "apply-auto")) {
        /* DISPATCH_APPLY_AUTO (10.12) names a global queue on 10.9, whose dispatch_apply needs a real one */
        __block long sum = 0;
        dispatch_queue_global_t g = DISPATCH_APPLY_AUTO;
        dispatch_apply(100, DISPATCH_APPLY_AUTO, ^(size_t i) { __sync_fetch_and_add(&sum, (long)i); });
        if (sum != 4950 || g == NULL) { printf("FAIL: dispatch_apply over DISPATCH_APPLY_AUTO summed %ld, want 4950\n", sum); return 1; }
        return 0;
    }
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
        __block volatile int ran = 0;
        dispatch_suspend(q1);
        dispatch_async(t, ^{ ran = 1; });
        usleep(200000);
        if (ran) { puts("FAIL: a block ran while the target queue was suspended"); return 1; }
        dispatch_resume(q1);
        dispatch_sync(t, ^{});
        return !ran;
    }
    if (!strcmp(c, "inactive-serial"))
        return starts_inactive(dispatch_queue_create("recaulk.in", dispatch_queue_attr_make_initially_inactive(NULL)), "a serial queue");
    if (!strcmp(c, "inactive-concurrent")) {
        dispatch_queue_t q = dispatch_queue_create("recaulk.inc", dispatch_queue_attr_make_initially_inactive(DISPATCH_QUEUE_CONCURRENT));
        if (starts_inactive(q, "a concurrent queue")) return 1;
        if (!runs_concurrently(q)) { puts("FAIL: the inactive attribute lost the concurrent one"); return 1; }
        return 0;
    }
    /* swift-gg on 10.9.5 with 20261120.3: Swift retains the attribute, and objc_retain read 'RCI1' as an isa */
    if (!strcmp(c, "inactive-attr-retained")) {
        dispatch_queue_attr_t attrs[] = { dispatch_queue_attr_make_initially_inactive(NULL),
                                          dispatch_queue_attr_make_initially_inactive(DISPATCH_QUEUE_CONCURRENT) };
        for (int i = 0; i < 2; i++) {
            void *a = objc_retain((void *)attrs[i]);
            if (a != (void *)attrs[i]) { puts("FAIL: objc_retain returned another object"); return 1; }
            if (!object_getClassName((id)a)) { puts("FAIL: the attribute has no class"); return 1; }
            dispatch_queue_t q = dispatch_queue_create("recaulk.inr", (dispatch_queue_attr_t)a);
            objc_release(a);
            if (starts_inactive(q, i ? "a concurrent queue from a retained attribute" : "a serial queue from a retained attribute")) return 1;
            if (i && !runs_concurrently(q)) { puts("FAIL: the retained inactive attribute lost the concurrent one"); return 1; }
        }
        return 0;
    }
    /* the attributes earlier Recaulks handed out, which a copy built from them may still pass in: 20261120.4 and
       earlier's 8-byte 'RCI1' struct, and 20261121.1-.6's object of a class registered at run time with 'RCI2' and
       the concurrency in its extra bytes; and every call gives the one process-wide attribute */
    if (!strcmp(c, "inactive-attr-earlier")) {
        static struct { uint32_t magic, concurrent; } v1 = { 0x52434931u, 1 };
        dispatch_queue_t q = dispatch_queue_create("recaulk.v1", (dispatch_queue_attr_t)(void *)&v1);
        if (starts_inactive(q, "a queue from a 20261120.4 attribute")) return 1;
        if (!runs_concurrently(q)) { puts("FAIL: the 20261120.4 attribute lost the concurrent one"); return 1; }
        Class k = objc_allocateClassPair(objc_getClass("NSObject"), "__RecaulkDispatchInactiveQueueAttribute_v2", 0);
        if (!k) { puts("FAIL: this Recaulk registered 20261121.1's class itself"); return 1; }
        objc_registerClassPair(k);
        id v2 = class_createInstance(k, 8);
        uint32_t *x = object_getIndexedIvars(v2);
        x[0] = 0x52434932u; x[1] = 1;
        q = dispatch_queue_create("recaulk.v2", (dispatch_queue_attr_t)(void *)v2);
        if (starts_inactive(q, "a queue from a 20261121.1 attribute")) return 1;
        if (!runs_concurrently(q)) { puts("FAIL: the 20261121.1 attribute lost the concurrent one"); return 1; }
        if (dispatch_queue_attr_make_initially_inactive(NULL) != dispatch_queue_attr_make_initially_inactive(NULL)) {
            puts("FAIL: two calls gave two serial attributes"); return 1;
        }
        return 0;
    }
    /* swift-gg 2026-11-20: a queue keeps the QoS class its attribute names, which 10.9's attributes had nowhere to
       keep, alone and with inactivity and concurrency in either order */
    if (!strcmp(c, "qos-kept")) {
        int rp = 7;
        dispatch_queue_t q = dispatch_queue_create("recaulk.qk",
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, -4));
        dispatch_qos_class_t k = dispatch_queue_get_qos_class(q, &rp);
        if (k != QOS_CLASS_UTILITY || rp != -4) { printf("FAIL: the queue reports class %#x, priority %d\n", k, rp); return 1; }
        if (!runs_within(q, 2000)) { puts("FAIL: a QoS queue ran nothing"); return 1; }
        return 0;
    }
    if (!strcmp(c, "qos-inactive-concurrent")) {
        dispatch_queue_attr_t orders[] = {
            dispatch_queue_attr_make_with_qos_class(dispatch_queue_attr_make_initially_inactive(DISPATCH_QUEUE_CONCURRENT),
                QOS_CLASS_USER_INITIATED, -2),
            dispatch_queue_attr_make_initially_inactive(dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT,
                QOS_CLASS_USER_INITIATED, -2)),
        };
        for (int i = 0; i < 2; i++) {
            int rp = 7;
            dispatch_queue_t q = dispatch_queue_create("recaulk.qic", orders[i]);
            dispatch_qos_class_t k = dispatch_queue_get_qos_class(q, &rp);
            if (k != QOS_CLASS_USER_INITIATED || rp != -2) { printf("FAIL: order %d: class %#x, priority %d\n", i, k, rp); return 1; }
            if (starts_inactive(q, i ? "an inactive concurrent queue made after its QoS" : "a QoS queue made after its inactivity")) return 1;
            if (!runs_concurrently(q)) { printf("FAIL: order %d lost the concurrent attribute\n", i); return 1; }
        }
        if (orders[0] != orders[1]) { puts("FAIL: the same attribute made in two orders is two objects"); return 1; }
        return 0;
    }
    if (!strcmp(c, "inactive-with-qos"))
        return starts_inactive(dispatch_queue_create("recaulk.inq", dispatch_queue_attr_make_with_qos_class(
            dispatch_queue_attr_make_initially_inactive(DISPATCH_QUEUE_SERIAL), QOS_CLASS_UTILITY, 0)), "a QoS queue");
    if (!strcmp(c, "inactive-with-target"))
        return starts_inactive(dispatch_queue_create_with_target("recaulk.int",
            dispatch_queue_attr_make_initially_inactive(NULL), q1), "a targeted queue");
    if (!strcmp(c, "activate-active-queue")) {
        dispatch_activate(q1);
        dispatch_activate(q1);
        if (!runs_within(q1, 2000)) { puts("FAIL: an active queue stopped after dispatch_activate"); return 1; }
        return 0;
    }
    if (!strcmp(c, "activate-source")) {
        dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, q1);
        dispatch_semaphore_t fired = dispatch_semaphore_create(0);
        dispatch_source_set_event_handler(s, ^{ dispatch_semaphore_signal(fired); });
        dispatch_activate(s);
        dispatch_activate(s);
        dispatch_source_merge_data(s, 1);
        if (dispatch_semaphore_wait(fired, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC))) { puts("FAIL: an activated source never fired"); return 1; }
        return 0;
    }
    if (!strcmp(c, "resumed-source-then-activate")) {
        dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, q1);
        dispatch_semaphore_t fired = dispatch_semaphore_create(0);
        dispatch_source_set_event_handler(s, ^{ dispatch_semaphore_signal(fired); });
        dispatch_resume(s);
        dispatch_activate(s);
        dispatch_source_merge_data(s, 1);
        if (dispatch_semaphore_wait(fired, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC))) { puts("FAIL: a resumed source never fired"); return 1; }
        return 0;
    }
    if (!strcmp(c, "resumed-inactive-then-activate")) {
        dispatch_queue_t q = dispatch_queue_create("recaulk.ri", dispatch_queue_attr_make_initially_inactive(NULL));
        dispatch_resume(q);
        dispatch_activate(q);
        if (!runs_within(q, 2000)) { puts("FAIL: an inactive queue resumed then activated ran no block"); return 1; }
        return 0;
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
