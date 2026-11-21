/* spec: README.md "Dispatch on 10.9" -- dispatch_block_wait, dispatch_block_notify, and a block's cancel and done
   state shared by every copy of Recaulk in the process: tests/dispatch-block-wait-test.sh runs each case.
   other_cancel and other_wait come from a dylib that links its own librecaulk.a (a second copy). */
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <Block.h>

void other_cancel(dispatch_block_t block);
long other_wait(dispatch_block_t block, dispatch_time_t timeout);
dispatch_queue_attr_t other_inactive_attr(int concurrent);
dispatch_queue_t other_create(const char *label, dispatch_queue_attr_t attr);

/* A queue made inactive runs nothing until dispatch_activate, then runs. */
static int inactive_then_runs(dispatch_queue_t iq) {
    __block volatile int r = 0;
    dispatch_async(iq, ^{ r = 1; });
    usleep(200000);
    if (r) return 0;
    dispatch_activate(iq);
    for (int i = 0; i < 200 && !r; i++) usleep(10000);
    return r;
}

#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); puts(""); return 1; } } while (0)

static dispatch_time_t in_ms(long ms) { return dispatch_time(DISPATCH_TIME_NOW, ms * (long)NSEC_PER_MSEC); }

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s CASE\n", argv[0]); return 2; }
    const char *c = argv[1];
    dispatch_queue_t q = dispatch_queue_create("recaulk.bw", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t nq = dispatch_queue_create("recaulk.bw.notify", DISPATCH_QUEUE_SERIAL);
    __block volatile int ran = 0, notified = 0;
    dispatch_block_t b = dispatch_block_create(0, ^{ usleep(100000); ran = 1; });

    if (!strcmp(c, "wait-after-async")) {
        dispatch_async(q, b);
        CHECK(dispatch_block_wait(b, DISPATCH_TIME_FOREVER) == 0, "wait gave non-zero");
        CHECK(ran, "wait returned before the block ran");
    } else if (!strcmp(c, "wait-finished")) {
        b();
        CHECK(dispatch_block_wait(b, DISPATCH_TIME_NOW) == 0, "a finished block's wait gave non-zero");
    } else if (!strcmp(c, "wait-timeout")) {
        CHECK(dispatch_block_wait(b, in_ms(200)) != 0, "a block never run gave 0");
        CHECK(!ran, "the block ran");
    } else if (!strcmp(c, "notify-after-async")) {
        dispatch_block_notify(b, nq, ^{ notified = ran ? 1 : -1; });
        dispatch_async(q, b);
        dispatch_sync(q, ^{});
        dispatch_sync(nq, ^{});
        CHECK(notified == 1, "notify %s", notified ? "ran before the block finished" : "never ran");
    } else if (!strcmp(c, "notify-finished")) {
        b();
        dispatch_block_notify(b, nq, ^{ notified = 1; });
        dispatch_sync(nq, ^{});
        CHECK(notified == 1, "notify on a finished block never ran");
    } else if (!strcmp(c, "cancelled-then-run")) {
        dispatch_block_notify(b, nq, ^{ notified = 1; });
        dispatch_block_cancel(b);
        dispatch_async(q, b);
        CHECK(dispatch_block_wait(b, in_ms(2000)) == 0, "a cancelled block, dequeued, did not finish");
        dispatch_sync(nq, ^{});
        CHECK(!ran, "a cancelled block ran its work");
        CHECK(notified == 1, "a cancelled block's notify never ran");
    } else if (!strcmp(c, "release-unrun-with-notify")) {
        dispatch_block_notify(b, nq, ^{ notified = 1; });
        Block_release(b);
        dispatch_sync(nq, ^{});
        CHECK(!notified, "notify ran for a block released unrun");
        return 0;
    } else if (!strcmp(c, "other-copy-cancels")) {
        other_cancel(b);
        CHECK(dispatch_block_testcancel(b), "another copy's cancel is not seen here");
        b();
        CHECK(!ran, "a block another copy cancelled ran its work");
    } else if (!strcmp(c, "other-copy-waits")) {
        dispatch_async(q, b);
        CHECK(other_wait(b, DISPATCH_TIME_FOREVER) == 0, "another copy's wait gave non-zero");
        CHECK(ran, "another copy's wait returned before the block ran");
    } else if (!strcmp(c, "other-copy-makes-inactive")) {
        CHECK(inactive_then_runs(dispatch_queue_create("recaulk.oi", other_inactive_attr(0))),
              "a serial queue from another copy's inactive attribute was not inactive, or never ran");
        CHECK(inactive_then_runs(dispatch_queue_create("recaulk.oic", other_inactive_attr(1))),
              "a concurrent queue from another copy's inactive attribute was not inactive, or never ran");
    } else if (!strcmp(c, "other-copy-honours-inactive")) {
        CHECK(inactive_then_runs(other_create("recaulk.ho", dispatch_queue_attr_make_initially_inactive(NULL))),
              "another copy made an active queue from this copy's inactive attribute");
        CHECK(dispatch_queue_attr_make_initially_inactive(other_inactive_attr(1)) == other_inactive_attr(1),
              "this copy did not recognise another copy's inactive attribute as one");
    } else { fprintf(stderr, "unknown case %s\n", c); return 2; }
    Block_release(b);
    return 0;
}
