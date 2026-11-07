#include_next <spawn.h>
#ifndef RECAULK_SPAWN_H
#define RECAULK_SPAWN_H
#ifndef __ASSEMBLER__
/* spec: the 11.3 SDK's spawn.h declares the chdir builders under exactly this condition; README.md "Child processes". */
#if !defined(_POSIX_C_SOURCE) || defined(_DARWIN_C_SOURCE)
__BEGIN_DECLS
int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *, const char * __restrict);
int posix_spawn_file_actions_addfchdir_np(posix_spawn_file_actions_t *, int);
__END_DECLS
#endif
#endif
#endif
