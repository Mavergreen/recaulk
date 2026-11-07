#include <os/_recaulk_macports_lock.h>
#ifndef RECAULK_OS_LOCK_H
#define RECAULK_OS_LOCK_H
/* spec: the 11.3 SDK's os/lock.h declares os_unfair_lock_assert_owner beside the lock MacPorts supplies;
   README.md "Declarations". */
__BEGIN_DECLS
void os_unfair_lock_assert_owner(os_unfair_lock_t lock);
__END_DECLS
#endif
