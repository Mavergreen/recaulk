#include_next <sys/_endian.h>
#ifndef RECAULK_SYS__ENDIAN_H
#define RECAULK_SYS__ENDIAN_H
/* spec: the 11.3 SDK's sys/_endian.h defines ntohll, htonll, NTOHLL and HTONLL beside ntohl, under the same
   conditions; README.md "Declarations". Its 10.10 SDK was the first to have them. */
#include <sys/cdefs.h>
#if !defined(ntohll) && (defined(KERNEL) || !defined(_POSIX_C_SOURCE) || defined(_DARWIN_C_SOURCE))
#if __DARWIN_BYTE_ORDER == __DARWIN_BIG_ENDIAN
#define ntohll(x)       ((__uint64_t)(x))
#define htonll(x)       ((__uint64_t)(x))
#define NTOHLL(x)       (x)
#define HTONLL(x)       (x)
#else
#include <libkern/_OSByteOrder.h>
#define ntohll(x)       __DARWIN_OSSwapInt64(x)
#define htonll(x)       __DARWIN_OSSwapInt64(x)
#define NTOHLL(x)       (x) = ntohll((__uint64_t)x)
#define HTONLL(x)       (x) = htonll((__uint64_t)x)
#endif
#endif
#endif
