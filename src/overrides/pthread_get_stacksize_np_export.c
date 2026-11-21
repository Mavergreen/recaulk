/*
 * pthread_get_stacksize_np, public, for libRecaulkSystem.dylib -- Recaulk's own (src/backfills/pthread_get_stacksize_np.c):
 * the main thread's size is the stack the kernel gave it. In the dylib this replaces the weak hidden copy librecaulk.a
 * keeps for the image that links it.
 */
#include <pthread.h>

size_t __recaulk_pthread_get_stacksize_np(pthread_t t);

size_t recaulk_export_pthread_get_stacksize_np(pthread_t) __asm("_pthread_get_stacksize_np");
size_t recaulk_export_pthread_get_stacksize_np(pthread_t t) { return __recaulk_pthread_get_stacksize_np(t); }
