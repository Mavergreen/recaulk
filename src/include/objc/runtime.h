#include_next <objc/runtime.h>
#ifndef RECAULK_OBJC_RUNTIME_H
#define RECAULK_OBJC_RUNTIME_H
/* spec: the 11.3 SDK's objc/runtime.h declares _objc_realizeClassFromSwift for every Mac but i386; README.md
   "Declarations". Not its OBJC_REALIZECLASSFROMSWIFT_DEFINED, which changes what Swift's runtime builds. */
#ifndef __i386__
OBJC_EXPORT Class _objc_realizeClassFromSwift(Class cls, void *previously);
#endif
#endif
