#ifndef RECAULK_REGISTER_COMMON_H
#define RECAULK_REGISTER_COMMON_H
#import <objc/runtime.h>
/* Adds SELECTOR to RECEIVER unless it or a superclass already implements it. A SEL, not a name: each caller makes
   it from a literal at the call, where Drydock's strict guard reads it (tests/objc-literal-selectors.sh). */
void __recaulk_objc_add_method(Class receiver, SEL selector, IMP imp, const char *encoding);
#endif
