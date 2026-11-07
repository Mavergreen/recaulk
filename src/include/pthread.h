#include <_recaulk_macports_pthread.h>
#ifndef RECAULK_PTHREAD_H
#define RECAULK_PTHREAD_H
#ifndef __ASSEMBLER__
/* spec: the 11.3 SDK's pthread/pthread.h declares pthread_jit_write_protect_np under exactly this condition. */
#if (!defined(_POSIX_C_SOURCE) && !defined(_XOPEN_SOURCE)) || defined(_DARWIN_C_SOURCE) || defined(__cplusplus)
__BEGIN_DECLS
void pthread_jit_write_protect_np(int enabled);
__END_DECLS
#endif
#endif
#endif
