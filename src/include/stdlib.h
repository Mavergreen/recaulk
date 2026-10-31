#include <_recaulk_macports/stdlib.h>
#ifndef RECAULK_STDLIB_H
#define RECAULK_STDLIB_H
#ifndef __ASSEMBLER__
#include <_macports_extras/sdkversion.h>
/* BSD bounded decimal conversion, missing from the Mavericks SDK. */
__BEGIN_DECLS
long long strtonum(const char *, long long, long long, const char **);
__END_DECLS
/* spec: the 11.3 SDK's malloc/_malloc.h declares aligned_alloc under exactly this condition. */
#if __MPLS_SDK_MAJOR < 101500 && ((__DARWIN_C_LEVEL >= __DARWIN_C_FULL) || \
    (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L) || \
    (defined(__cplusplus) && __cplusplus >= 201703L))
__BEGIN_DECLS
void *aligned_alloc(size_t __alignment, size_t __size);
__END_DECLS
#endif
#endif
#endif
