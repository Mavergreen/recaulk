/* spec: README.md "Dispatch on 10.9" -- a second image with its own copy of librecaulk.a's dispatch blocks. */
#include <dispatch/dispatch.h>
void other_cancel(dispatch_block_t block) { dispatch_block_cancel(block); }
long other_wait(dispatch_block_t block, dispatch_time_t timeout) { return dispatch_block_wait(block, timeout); }
/* spec: README.md "Dispatch on 10.9" -- an initially inactive attribute one copy makes, the other copy honours */
dispatch_queue_attr_t other_inactive_attr(int concurrent) {
    return dispatch_queue_attr_make_initially_inactive(concurrent ? DISPATCH_QUEUE_CONCURRENT : DISPATCH_QUEUE_SERIAL);
}
dispatch_queue_t other_create(const char *label, dispatch_queue_attr_t attr) { return dispatch_queue_create(label, attr); }
