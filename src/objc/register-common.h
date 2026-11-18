#ifndef RECAULK_REGISTER_COMMON_H
#define RECAULK_REGISTER_COMMON_H
#import <objc/runtime.h>
/* Adds NAME to RECEIVER unless it or a superclass already implements it. */
void __recaulk_objc_add_method(Class receiver, const char *name, IMP imp, const char *encoding);
#endif
