/* spec: README.md "Fixes to functions 10.9 has" -- declared before 10.9's own declaration, so a program built
   from source calls Recaulk's fix whatever its link order (a -lm or -lc ahead of librecaulk.a names libSystem,
   whose copy would otherwise bind first). Not inside Recaulk, whose own sources define the 10.9 names. */
#ifndef RECAULK_NAMES_SPAWN_H
#define RECAULK_NAMES_SPAWN_H
#ifndef __RECAULK_SOURCE__
#include <sys/types.h>
/* platform: as the 10.9 SDK's spawn.h, which these must precede, types them */
typedef void *posix_spawnattr_t;
typedef void *posix_spawn_file_actions_t;
#ifdef __cplusplus
extern "C" {
#endif
int posix_spawn(pid_t * __restrict, const char * __restrict, const posix_spawn_file_actions_t *,
    const posix_spawnattr_t * __restrict, char *const __argv[ __restrict], char *const __envp[ __restrict])
    __asm("___recaulk_posix_spawn_entry");
int posix_spawnp(pid_t * __restrict, const char * __restrict, const posix_spawn_file_actions_t *,
    const posix_spawnattr_t * __restrict, char *const __argv[ __restrict], char *const __envp[ __restrict])
    __asm("___recaulk_posix_spawnp_entry");
int posix_spawn_file_actions_init(posix_spawn_file_actions_t *) __asm("___recaulk_posix_spawn_file_actions_init");
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *) __asm("___recaulk_posix_spawn_file_actions_destroy");
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *, int)
    __asm("___recaulk_posix_spawn_file_actions_addclose");
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *, int, int)
    __asm("___recaulk_posix_spawn_file_actions_adddup2");
int posix_spawn_file_actions_addinherit_np(posix_spawn_file_actions_t *, int)
    __asm("___recaulk_posix_spawn_file_actions_addinherit_np");
int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t * __restrict, int, const char * __restrict, int, mode_t)
    __asm("___recaulk_posix_spawn_file_actions_addopen");
#ifdef __cplusplus
}
#endif
#endif
#endif
