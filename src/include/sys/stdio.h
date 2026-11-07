#include <sys/_recaulk_macports_stdio.h>
#ifndef RECAULK_SYS_STDIO_H
#define RECAULK_SYS_STDIO_H
#ifndef __ASSEMBLER__
/* spec: the 11.3 SDK's sys/stdio.h declares renameatx_np under exactly this condition (inside __DARWIN_C_LEVEL >= 200809L, which it implies). */
#if __DARWIN_C_LEVEL >= __DARWIN_C_FULL
__BEGIN_DECLS
int renameatx_np(int, const char *, int, const char *, unsigned int);
__END_DECLS
#endif
#endif
#endif
