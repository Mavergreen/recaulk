#include <_recaulk_macports_string.h>
#ifndef RECAULK_STRING_H
#define RECAULK_STRING_H
#ifndef __ASSEMBLER__
/* spec: the 11.3 SDK's string.h declares timingsafe_bcmp under exactly this condition. */
#if __DARWIN_C_LEVEL >= __DARWIN_C_FULL
__BEGIN_DECLS
int timingsafe_bcmp(const void *__b1, const void *__b2, size_t __len);
__END_DECLS
#endif
#endif
#endif
