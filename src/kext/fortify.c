/* spec: README.md "The kernel back-fill kext" -- the compiler-emitted fortify checks macFUSE imports, as
   xnu-8019.41.5 osfmk/device/subrs.c:645-651, 691-698 define them: panic when the copy is longer than the
   destination, else the plain call. 10.9's kernel has neither. */
#include <kern/debug.h>
#include <string.h>

#define RK_EXPORT __attribute__((visibility("default"), used))

RK_EXPORT void *
__memcpy_chk(void *dst, const void *src, size_t n, size_t dstlen)
{
	if (n > dstlen) {
		panic("__memcpy_chk object size check failed: dst %p, src %p, (%lu > %lu)",
		    dst, src, (unsigned long)n, (unsigned long)dstlen);
	}
	return memcpy(dst, src, n);
}

RK_EXPORT char *
__strncpy_chk(char *dst, const char *src, size_t n, size_t dstlen)
{
	if (n > dstlen) {
		panic("__strncpy_chk object size check failed: dst %p, src %p, (%lu > %lu)",
		    dst, src, (unsigned long)n, (unsigned long)dstlen);
	}
	return strncpy(dst, src, n);
}
