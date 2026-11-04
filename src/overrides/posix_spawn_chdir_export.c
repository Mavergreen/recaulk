/*
 * posix_spawn, posix_spawnp and the posix_spawn_file_actions_t init, destroy and builders 10.9 has,
 * public, for libRecaulkSystem.dylib -- Recaulk's own. A program relinked onto the dylib binds these
 * names to it, so its chdir actions (src/backfills/posix_spawn_chdir.c) are carried out too. In the
 * dylib these replace the weak hidden copies that librecaulk.a keeps for the image that links it.
 */
#include <spawn.h>

int __recaulk_posix_spawn(int search, pid_t *pid, const char *file,
                          const posix_spawn_file_actions_t *file_actions,
                          const posix_spawnattr_t *attr, char *const argv[], char *const envp[]);
int __recaulk_posix_spawn_file_actions_init(posix_spawn_file_actions_t *file_actions);
int __recaulk_posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *file_actions);
int __recaulk_posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *file_actions, int fd);
int __recaulk_posix_spawn_file_actions_addinherit_np(posix_spawn_file_actions_t *file_actions, int fd);
int __recaulk_posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *file_actions, int fd, int newfd);
int __recaulk_posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *file_actions, int fd,
                                               const char *path, int oflag, mode_t mode);

int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions,
                const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    return __recaulk_posix_spawn(0, pid, path, file_actions, attr, argv, envp);
}

int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions,
                 const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    return __recaulk_posix_spawn(1, pid, file, file_actions, attr, argv, envp);
}

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *file_actions) {
    return __recaulk_posix_spawn_file_actions_init(file_actions);
}

int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *file_actions) {
    return __recaulk_posix_spawn_file_actions_destroy(file_actions);
}

int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *file_actions, int fd) {
    return __recaulk_posix_spawn_file_actions_addclose(file_actions, fd);
}

int posix_spawn_file_actions_addinherit_np(posix_spawn_file_actions_t *file_actions, int fd) {
    return __recaulk_posix_spawn_file_actions_addinherit_np(file_actions, fd);
}

int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *file_actions, int fd, int newfd) {
    return __recaulk_posix_spawn_file_actions_adddup2(file_actions, fd, newfd);
}

int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *file_actions, int fd,
                                     const char *path, int oflag, mode_t mode) {
    return __recaulk_posix_spawn_file_actions_addopen(file_actions, fd, path, oflag, mode);
}
