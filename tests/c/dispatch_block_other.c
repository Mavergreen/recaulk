/* spec: README.md "Dispatch on 10.9" -- a second image with its own copy of librecaulk.a's dispatch blocks. */
#include <dispatch/dispatch.h>
void other_cancel(dispatch_block_t block) { dispatch_block_cancel(block); }
long other_wait(dispatch_block_t block, dispatch_time_t timeout) { return dispatch_block_wait(block, timeout); }
