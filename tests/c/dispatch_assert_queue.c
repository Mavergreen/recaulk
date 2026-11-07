#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void assert_queue(dispatch_queue_t) __asm("_dispatch_assert_queue$V2");

static dispatch_queue_t q1, q2, inner;

static void *on_pthread(void *queue) {
    assert_queue(queue);
    return NULL;
}

static void from_pthread(dispatch_queue_t queue) {
    pthread_t t;
    pthread_create(&t, NULL, on_pthread, queue);
    pthread_join(t, NULL);
}

static void from_worker_while_main_waits(dispatch_queue_t queue) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        assert_queue(queue);
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s CASE\n", argv[0]); return 2; }
    const char *c = argv[1];
    q1 = dispatch_queue_create("recaulk.q1", DISPATCH_QUEUE_SERIAL);
    q2 = dispatch_queue_create("recaulk.q2", DISPATCH_QUEUE_SERIAL);
    inner = dispatch_queue_create("recaulk.inner", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(inner, q1);
    dispatch_queue_t global = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    if (!strcmp(c, "main-on-main-thread")) assert_queue(dispatch_get_main_queue());
    else if (!strcmp(c, "serial-on-main-thread")) assert_queue(q1);
    else if (!strcmp(c, "global-on-main-thread")) assert_queue(global);
    else if (!strcmp(c, "serial-in-main-block")) {
        dispatch_async(dispatch_get_main_queue(), ^{ assert_queue(q1); exit(0); });
        dispatch_main();
    }
    else if (!strcmp(c, "main-in-main-block")) {
        dispatch_async(dispatch_get_main_queue(), ^{ assert_queue(dispatch_get_main_queue()); exit(0); });
        dispatch_main();
    }
    else if (!strcmp(c, "main-in-sync-from-main-thread")) dispatch_sync(q1, ^{ assert_queue(dispatch_get_main_queue()); });
    else if (!strcmp(c, "serial-in-sync")) dispatch_sync(q1, ^{ assert_queue(q1); });
    else if (!strcmp(c, "serial-in-async")) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(q1, ^{ assert_queue(q1); dispatch_semaphore_signal(done); });
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    }
    else if (!strcmp(c, "target-in-block")) dispatch_sync(inner, ^{ assert_queue(q1); });
    else if (!strcmp(c, "global-in-block")) dispatch_sync(global, ^{ assert_queue(global); });
    else if (!strcmp(c, "outer-in-nested-sync")) dispatch_sync(q1, ^{ dispatch_sync(q2, ^{ assert_queue(q1); }); });
    else if (!strcmp(c, "other-queue-block")) dispatch_sync(q2, ^{ assert_queue(q1); });
    else if (!strcmp(c, "main-outer-in-nested-sync-after-dispatch-main")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            dispatch_sync(q2, ^{ assert_queue(dispatch_get_main_queue()); });
            exit(0);
        });
        dispatch_main();
    }
    else if (!strcmp(c, "serial-off-on-pthread")) from_pthread(q1);
    else if (!strcmp(c, "main-off-on-pthread")) from_pthread(dispatch_get_main_queue());
    else if (!strcmp(c, "global-off-on-pthread")) from_pthread(global);
    else if (!strcmp(c, "main-off-in-worker")) from_worker_while_main_waits(dispatch_get_main_queue());
    else if (!strcmp(c, "target-off-after-block")) { dispatch_sync(inner, ^{}); from_pthread(q1); }
    else if (!strcmp(c, "null")) assert_queue(NULL);
    else { fprintf(stderr, "unknown case %s\n", c); return 2; }
    return 0;
}
