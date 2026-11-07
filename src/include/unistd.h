#include <_recaulk_macports_unistd.h>
#ifndef RECAULK_UNISTD_H
#define RECAULK_UNISTD_H
#ifndef __ASSEMBLER__
/* spec: the 11.3 SDK's unistd.h declares mkostemp under exactly this condition. */
#if __DARWIN_C_LEVEL >= __DARWIN_C_FULL
__BEGIN_DECLS
int mkostemp(char *path, int oflags);
__END_DECLS
#endif
#endif
#endif
