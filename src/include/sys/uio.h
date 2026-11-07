#include_next <sys/uio.h>
#ifndef RECAULK_SYS_UIO_H
#define RECAULK_SYS_UIO_H
#ifndef __ASSEMBLER__
/* spec: the 11.3 SDK's sys/uio.h declares preadv and pwritev under exactly this condition; README.md "Vector I/O at an offset".
   Without its __DARWIN_NOCANCEL label, which 10.9's sys/cdefs.h lacks: the plain names are Recaulk's. */
#if (!defined(_POSIX_C_SOURCE) && !defined(_XOPEN_SOURCE)) || defined(_DARWIN_C_SOURCE)
__BEGIN_DECLS
ssize_t preadv(int, const struct iovec *, int, off_t);
ssize_t pwritev(int, const struct iovec *, int, off_t);
__END_DECLS
#endif
#endif
#endif
