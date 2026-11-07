#include_next <os/object.h>
#ifndef RECAULK_OS_OBJECT_H
#define RECAULK_OS_OBJECT_H
#include <sys/cdefs.h>
/* spec: the 11.3 SDK's os/object.h declares os_release, and makes it a message under Objective-C's
   OS_OBJECT_USE_OBJC; README.md "Declarations". */
__BEGIN_DECLS
void os_release(void *object);
__END_DECLS
#if OS_OBJECT_USE_OBJC
#undef os_release
#define os_release(object) [object release]
#endif
#endif
