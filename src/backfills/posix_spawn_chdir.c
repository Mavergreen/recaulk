/*
 * posix_spawn_file_actions_addchdir_np and posix_spawn_file_actions_addfchdir_np (macOS 10.15) for
 * 10.9, with the posix_spawn and posix_spawnp that carry them out -- Recaulk's own rewrite of
 * Wowfunhappy's override of the same name. The generated forwarding layer prefers the native
 * builders on newer macOS, and the system's posix_spawn then carries out its own chdir actions.
 *
 * 10.9's posix_spawn has no chdir action, so the builders record each one beside the actions object,
 * in order, keyed by the object *file_actions points at. libSystem reallocs that object as it grows,
 * so the system's other builders (addopen, adddup2, addclose, addinherit_np) are wrapped too: around
 * any call on an object with recorded actions they hold the record's lock and move the key to
 * wherever the object went. posix_spawn and posix_spawnp take the
 * recorded directories in the calling thread alone, with pthread_chdir_np and pthread_fchdir_np,
 * call the system's posix_spawn (whose child starts in the thread's directory, and resolves the
 * program path, a PATH search and every relative open action there), and put the thread back on
 * the process's directory. No other thread's directory ever moves. With POSIX_SPAWN_SETEXEC the
 * program that replaces this process starts in the thread's directory just the same.
 *
 * Every chdir action is taken before the system's actions, not in its place among them: a relative
 * open action added before the chdir action resolves in the new directory too, and a dup2 or close
 * action does not change the descriptor addfchdir_np named.
 *
 * posix_spawn, posix_spawnp and the actions object's init, destroy and other builders are 10.9
 * exports, so here they are weak and hidden (build/image-local-shadows.txt, rule 1's one
 * exception): they bind only inside the image that links librecaulk.a, and yield to the public ones
 * src/overrides/posix_spawn_chdir_export.c gives libRecaulkSystem.dylib. init and destroy forget an
 * object's recorded directories, so a new object at a freed one's address starts with none. An
 * object grown by another image, which does not bind to these, loses its recorded directories.
 */
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int pthread_chdir_np(const char *path);
int pthread_fchdir_np(int fd);
int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *file_actions, const char *path);
int posix_spawn_file_actions_addfchdir_np(posix_spawn_file_actions_t *file_actions, int fd);

typedef int spawn_fn(pid_t *, const char *, const posix_spawn_file_actions_t *,
                     const posix_spawnattr_t *, char *const[], char *const[]);
typedef int actions_fn(posix_spawn_file_actions_t *);
typedef int fd_action_fn(posix_spawn_file_actions_t *, int);
typedef int dup2_action_fn(posix_spawn_file_actions_t *, int, int);
typedef int open_action_fn(posix_spawn_file_actions_t *, int, const char *, int, mode_t);

struct chdir_action {
    struct chdir_action *next;
    int fd;
    char path[];
};
struct chdir_actions {
    struct chdir_actions *next;
    const void *object;
    struct chdir_action *first, **last;
};
/* Written under recorded_lock; read without it only to see that nothing is recorded, so a process
 * that never records a chdir action never takes the lock. */
static struct chdir_actions *recorded;
static pthread_mutex_t recorded_lock = PTHREAD_MUTEX_INITIALIZER;

static int none_recorded(void) {
    return __atomic_load_n(&recorded, __ATOMIC_ACQUIRE) == NULL;
}

static struct chdir_actions **find(const void *object) {
    struct chdir_actions **at;
    for (at = &recorded; *at && (*at)->object != object; at = &(*at)->next) {}
    return at;
}

static int record(posix_spawn_file_actions_t *file_actions, const char *path, int fd) {
    size_t len = path ? strlen(path) : 0;
    struct chdir_action *action;
    struct chdir_actions **at;
    if (path && len >= PATH_MAX) return ENAMETOOLONG;
    action = malloc(sizeof *action + len + 1);
    if (!action) return ENOMEM;
    action->next = NULL;
    action->fd = fd;
    memcpy(action->path, path ? path : "", len + 1);
    pthread_mutex_lock(&recorded_lock);
    at = find(*file_actions);
    if (!*at) {
        struct chdir_actions *added = malloc(sizeof *added);
        if (!added) {
            pthread_mutex_unlock(&recorded_lock);
            free(action);
            return ENOMEM;
        }
        added->next = recorded;
        added->object = *file_actions;
        added->first = NULL;
        added->last = &added->first;
        __atomic_store_n(&recorded, added, __ATOMIC_RELEASE);
        at = &recorded;
    }
    *(*at)->last = action;
    (*at)->last = &action->next;
    pthread_mutex_unlock(&recorded_lock);
    return 0;
}

static void forget(const posix_spawn_file_actions_t *file_actions) {
    struct chdir_actions **at, *gone = NULL;
    struct chdir_action *action, *next;
    if (!file_actions || !*file_actions || none_recorded()) return;
    pthread_mutex_lock(&recorded_lock);
    at = find(*file_actions);
    if (*at) {
        gone = *at;
        __atomic_store_n(at, gone->next, __ATOMIC_RELEASE);
    }
    pthread_mutex_unlock(&recorded_lock);
    if (!gone) return;
    for (action = gone->first; action; action = next) {
        next = action->next;
        free(action);
    }
    free(gone);
}

/* The caller owns the actions object and may not change it while a spawn reads it, so the list
 * found here stays put once the lock is released. */
static const struct chdir_action *recorded_for(const posix_spawn_file_actions_t *file_actions) {
    struct chdir_actions **at;
    const struct chdir_action *first;
    if (!file_actions || !*file_actions || none_recorded()) return NULL;
    pthread_mutex_lock(&recorded_lock);
    at = find(*file_actions);
    first = *at ? (*at)->first : NULL;
    pthread_mutex_unlock(&recorded_lock);
    return first;
}

/* Around a system builder that may realloc the object: with actions recorded for it, hold the lock
 * through the call, so no init can forget the freed address before the key follows the object. */
static struct chdir_actions *hold(const posix_spawn_file_actions_t *file_actions) {
    struct chdir_actions *held;
    if (!file_actions || !*file_actions || none_recorded()) return NULL;
    pthread_mutex_lock(&recorded_lock);
    held = *find(*file_actions);
    if (!held) pthread_mutex_unlock(&recorded_lock);
    return held;
}

static void follow(struct chdir_actions *held, const posix_spawn_file_actions_t *file_actions) {
    if (!held) return;
    if (*file_actions) held->object = *file_actions;
    pthread_mutex_unlock(&recorded_lock);
}

int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *file_actions, const char *path) {
    if (!file_actions || !*file_actions || !path) return EINVAL;
    return record(file_actions, path, -1);
}

int posix_spawn_file_actions_addfchdir_np(posix_spawn_file_actions_t *file_actions, int fd) {
    if (!file_actions || !*file_actions) return EINVAL;
    if (fd < 0 || fd >= OPEN_MAX) return EBADF;
    return record(file_actions, NULL, fd);
}

static void *system_function(void **cache, const char *name) {
    void *found = __atomic_load_n(cache, __ATOMIC_ACQUIRE);
    if (!found) {
        found = dlsym(RTLD_NEXT, name);
        __atomic_store_n(cache, found, __ATOMIC_RELEASE);
    }
    return found;
}

static int take(const struct chdir_action *action) {
    for (; action; action = action->next)
        if ((action->fd >= 0 ? pthread_fchdir_np(action->fd) : pthread_chdir_np(action->path)) != 0) return errno;
    return 0;
}

int __recaulk_posix_spawn(int search, pid_t *pid, const char *file,
                          const posix_spawn_file_actions_t *file_actions,
                          const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    static void *spawn, *spawnp;
    spawn_fn *system_spawn = search ? (spawn_fn *)system_function(&spawnp, "posix_spawnp")
                                    : (spawn_fn *)system_function(&spawn, "posix_spawn");
    const struct chdir_action *actions = recorded_for(file_actions);
    int rc, saved_errno;
    if (!system_spawn) return ENOSYS;
    if (!actions) return system_spawn(pid, file, file_actions, attr, argv, envp);
    saved_errno = errno;
    rc = take(actions);
    if (rc == 0) rc = system_spawn(pid, file, file_actions, attr, argv, envp);
    (void)pthread_fchdir_np(-1);
    errno = saved_errno;
    return rc;
}

int __recaulk_posix_spawn_file_actions_init(posix_spawn_file_actions_t *file_actions) {
    static void *init;
    actions_fn *system_init = (actions_fn *)system_function(&init, "posix_spawn_file_actions_init");
    int rc;
    if (!system_init) return ENOSYS;
    rc = system_init(file_actions);
    if (rc == 0) forget(file_actions);
    return rc;
}

int __recaulk_posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *file_actions) {
    static void *destroy;
    actions_fn *system_destroy = (actions_fn *)system_function(&destroy, "posix_spawn_file_actions_destroy");
    if (!system_destroy) return ENOSYS;
    forget(file_actions);
    return system_destroy(file_actions);
}

int __recaulk_posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *file_actions, int fd) {
    static void *addclose;
    fd_action_fn *system_addclose = (fd_action_fn *)system_function(&addclose, "posix_spawn_file_actions_addclose");
    struct chdir_actions *held;
    int rc;
    if (!system_addclose) return ENOSYS;
    held = hold(file_actions);
    rc = system_addclose(file_actions, fd);
    follow(held, file_actions);
    return rc;
}

int __recaulk_posix_spawn_file_actions_addinherit_np(posix_spawn_file_actions_t *file_actions, int fd) {
    static void *addinherit;
    fd_action_fn *system_addinherit = (fd_action_fn *)system_function(&addinherit, "posix_spawn_file_actions_addinherit_np");
    struct chdir_actions *held;
    int rc;
    if (!system_addinherit) return ENOSYS;
    held = hold(file_actions);
    rc = system_addinherit(file_actions, fd);
    follow(held, file_actions);
    return rc;
}

int __recaulk_posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *file_actions, int fd, int newfd) {
    static void *adddup2;
    dup2_action_fn *system_adddup2 = (dup2_action_fn *)system_function(&adddup2, "posix_spawn_file_actions_adddup2");
    struct chdir_actions *held;
    int rc;
    if (!system_adddup2) return ENOSYS;
    held = hold(file_actions);
    rc = system_adddup2(file_actions, fd, newfd);
    follow(held, file_actions);
    return rc;
}

int __recaulk_posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *file_actions, int fd,
                                               const char *path, int oflag, mode_t mode) {
    static void *addopen;
    open_action_fn *system_addopen = (open_action_fn *)system_function(&addopen, "posix_spawn_file_actions_addopen");
    struct chdir_actions *held;
    int rc;
    if (!system_addopen) return ENOSYS;
    held = hold(file_actions);
    rc = system_addopen(file_actions, fd, path, oflag, mode);
    follow(held, file_actions);
    return rc;
}

/* spec: README.md "Fixes to functions 10.9 has" -- the names <spawn.h> gives posix_spawn and posix_spawnp in a
   program built from source. Public, so they bind whatever the link order. */
int __recaulk_posix_spawn_entry(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions,
                                const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    return __recaulk_posix_spawn(0, pid, path, file_actions, attr, argv, envp);
}

int __recaulk_posix_spawnp_entry(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions,
                                 const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    return __recaulk_posix_spawn(1, pid, file, file_actions, attr, argv, envp);
}

#define IMAGE_LOCAL __attribute__((weak, visibility("hidden")))

IMAGE_LOCAL int image_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions,
                                  const posix_spawnattr_t *attr, char *const argv[], char *const envp[])
    __asm("_posix_spawn");
IMAGE_LOCAL int image_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions,
                                  const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    return __recaulk_posix_spawn(0, pid, path, file_actions, attr, argv, envp);
}

IMAGE_LOCAL int image_posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions,
                                   const posix_spawnattr_t *attr, char *const argv[], char *const envp[])
    __asm("_posix_spawnp");
IMAGE_LOCAL int image_posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions,
                                   const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    return __recaulk_posix_spawn(1, pid, file, file_actions, attr, argv, envp);
}

IMAGE_LOCAL int image_file_actions_init(posix_spawn_file_actions_t *file_actions)
    __asm("_posix_spawn_file_actions_init");
IMAGE_LOCAL int image_file_actions_init(posix_spawn_file_actions_t *file_actions) {
    return __recaulk_posix_spawn_file_actions_init(file_actions);
}

IMAGE_LOCAL int image_file_actions_destroy(posix_spawn_file_actions_t *file_actions)
    __asm("_posix_spawn_file_actions_destroy");
IMAGE_LOCAL int image_file_actions_destroy(posix_spawn_file_actions_t *file_actions) {
    return __recaulk_posix_spawn_file_actions_destroy(file_actions);
}

IMAGE_LOCAL int image_file_actions_addclose(posix_spawn_file_actions_t *file_actions, int fd)
    __asm("_posix_spawn_file_actions_addclose");
IMAGE_LOCAL int image_file_actions_addclose(posix_spawn_file_actions_t *file_actions, int fd) {
    return __recaulk_posix_spawn_file_actions_addclose(file_actions, fd);
}

IMAGE_LOCAL int image_file_actions_addinherit_np(posix_spawn_file_actions_t *file_actions, int fd)
    __asm("_posix_spawn_file_actions_addinherit_np");
IMAGE_LOCAL int image_file_actions_addinherit_np(posix_spawn_file_actions_t *file_actions, int fd) {
    return __recaulk_posix_spawn_file_actions_addinherit_np(file_actions, fd);
}

IMAGE_LOCAL int image_file_actions_adddup2(posix_spawn_file_actions_t *file_actions, int fd, int newfd)
    __asm("_posix_spawn_file_actions_adddup2");
IMAGE_LOCAL int image_file_actions_adddup2(posix_spawn_file_actions_t *file_actions, int fd, int newfd) {
    return __recaulk_posix_spawn_file_actions_adddup2(file_actions, fd, newfd);
}

IMAGE_LOCAL int image_file_actions_addopen(posix_spawn_file_actions_t *file_actions, int fd,
                                           const char *path, int oflag, mode_t mode)
    __asm("_posix_spawn_file_actions_addopen");
IMAGE_LOCAL int image_file_actions_addopen(posix_spawn_file_actions_t *file_actions, int fd,
                                           const char *path, int oflag, mode_t mode) {
    return __recaulk_posix_spawn_file_actions_addopen(file_actions, fd, path, oflag, mode);
}
