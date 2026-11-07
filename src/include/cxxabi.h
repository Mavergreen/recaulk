#include_next <cxxabi.h>
#ifndef RECAULK_CXXABI_H
#define RECAULK_CXXABI_H
/* spec: the 11.3 SDK's cxxabi.h declares these in __cxxabiv1; README.md "Declarations". */
#ifdef __cplusplus
namespace __cxxabiv1 {
extern "C" {
__attribute__((__visibility__("default"), __noreturn__)) void __cxa_throw_bad_array_new_length(void);
__attribute__((__visibility__("default"))) unsigned int __cxa_uncaught_exceptions() throw();
}
}
#endif
#endif
