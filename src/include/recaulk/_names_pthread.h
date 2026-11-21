/* spec: README.md "Fixes to functions 10.9 has" -- declared before 10.9's own declaration, so a program built
   from source calls Recaulk's fix whatever its link order (a -lpthread or -lc ahead of librecaulk.a names
   libSystem, whose copy would otherwise bind first). Not inside Recaulk, whose own sources define the 10.9 names. */
#ifndef RECAULK_NAMES_PTHREAD_H
#define RECAULK_NAMES_PTHREAD_H
#ifndef __RECAULK_SOURCE__
/* platform: the 10.9 and 11.3 SDKs both define these in sys/_types.h, and keep pthread_t in different headers */
#include <sys/_types.h>
#ifdef __cplusplus
extern "C" {
#endif
__darwin_size_t pthread_get_stacksize_np(__darwin_pthread_t) __asm("___recaulk_pthread_get_stacksize_np");
#ifdef __cplusplus
}
#endif
#endif
#endif
