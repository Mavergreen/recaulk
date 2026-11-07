#include_next <sys/_types/_fd_def.h>
#ifndef RECAULK_SYS_TYPES_FD_DEF_H
#define RECAULK_SYS_TYPES_FD_DEF_H
#ifndef __ASSEMBLER__
/* spec: the 11.3 SDK's sys/_types/_fd_def.h declares __darwin_check_fd_set_overflow beside fd_set. */
__BEGIN_DECLS
int __darwin_check_fd_set_overflow(int, const void *, int);
__END_DECLS
#endif
#endif
