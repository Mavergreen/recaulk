/* Catch missing exports, a chdir action the child never takes, and a parent whose cwd moves. */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

/* The 10.9 SDK declares neither; macOS 10.15 declares them in <spawn.h>. */
extern int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *, const char *);
extern int posix_spawn_file_actions_addfchdir_np(posix_spawn_file_actions_t *, int);
extern char **environ;

static int failures;
#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static char base[PATH_MAX], sub[PATH_MAX], other[PATH_MAX], start[PATH_MAX];

/* Each actions object gets its chdir actions first and then a child's usual stdio, as Zig sets one
 * up: stdin from /dev/null, stdout to OUT_FD, which run() points at a fresh pipe before each spawn
 * so one object can be spawned from again and again, stderr kept, OUT_FD closed. Four actions
 * outgrow the object's first allocation, so libSystem reallocs it after the chdir is recorded. */
#define OUT_FD 100
static void actions(posix_spawn_file_actions_t *fa) {
    posix_spawn_file_actions_init(fa);
}
static void stdio(posix_spawn_file_actions_t *fa) {
    CHECK(posix_spawn_file_actions_addopen(fa, 0, "/dev/null", O_RDONLY, 0) == 0);
    CHECK(posix_spawn_file_actions_adddup2(fa, OUT_FD, 1) == 0);
    CHECK(posix_spawn_file_actions_adddup2(fa, 2, 2) == 0);
    CHECK(posix_spawn_file_actions_addclose(fa, OUT_FD) == 0);
}

/* Spawn argv[0] (by path, or by PATH search when search is set); return posix_spawn's result and
 * the child's output, trailing newline removed. */
static int run(posix_spawn_file_actions_t *fa, posix_spawnattr_t *attr, int search, char *const argv[], char *out, size_t outlen) {
    int p[2], rc, st;
    pid_t pid;
    ssize_t n, got = 0;
    if (pipe(p) != 0) return errno;
    dup2(p[1], OUT_FD);
    close(p[1]);
    rc = search ? posix_spawnp(&pid, argv[0], fa, attr, argv, environ)
                : posix_spawn(&pid, argv[0], fa, attr, argv, environ);
    close(OUT_FD);
    while (rc == 0 && (n = read(p[0], out + got, outlen - 1 - (size_t)got)) > 0) got += n;
    close(p[0]);
    out[got] = 0;
    if (got && out[got - 1] == '\n') out[got - 1] = 0;
    if (rc == 0) waitpid(pid, &st, 0);
    return rc;
}

static int pwd_in(posix_spawn_file_actions_t *fa, char *out) {
    char *argv[] = {"/bin/pwd", "-P", NULL};
    return run(fa, NULL, 0, argv, out, PATH_MAX);
}

static void parent_unmoved(void) {
    char now[PATH_MAX];
    CHECK(getcwd(now, sizeof now) && strcmp(now, start) == 0);
}

static volatile int watching = 1, moved;
static void *watch(void *unused) {
    char now[PATH_MAX];
    (void)unused;
    while (watching)
        if (!getcwd(now, sizeof now) || strcmp(now, start) != 0) moved = 1;
    return NULL;
}

int main(void) {
    posix_spawn_file_actions_t fa;
    char out[PATH_MAX];
    char tmpl[] = "/tmp/recaulk-spawn.XXXXXX";
    int fd;

    CHECK(mkdtemp(tmpl) != NULL);
    CHECK(realpath(tmpl, base) != NULL);
    snprintf(sub, sizeof sub, "%s/sub", base);
    snprintf(other, sizeof other, "%s/other", base);
    CHECK(mkdir(sub, 0700) == 0 && mkdir(other, 0700) == 0);
    CHECK(chdir("/") == 0 && getcwd(start, sizeof start) != NULL);

    /* addchdir_np, by absolute path. */
    actions(&fa);
    CHECK(posix_spawn_file_actions_addchdir_np(&fa, sub) == 0);
    stdio(&fa);
    CHECK(pwd_in(&fa, out) == 0 && strcmp(out, sub) == 0);
    parent_unmoved();
    /* The same actions, reused, chdir again. */
    CHECK(pwd_in(&fa, out) == 0 && strcmp(out, sub) == 0);
    posix_spawn_file_actions_destroy(&fa);

    /* addfchdir_np, then posix_spawnp. */
    fd = open(other, O_RDONLY);
    CHECK(fd >= 0);
    actions(&fa);
    CHECK(posix_spawn_file_actions_addfchdir_np(&fa, fd) == 0);
    {
        char *argv[] = {"pwd", "-P", NULL};
        stdio(&fa);
        CHECK(run(&fa, NULL, 1, argv, out, sizeof out) == 0 && strcmp(out, other) == 0);
    }
    posix_spawn_file_actions_destroy(&fa);
    parent_unmoved();

    /* Several chdir actions apply in order, a relative one from the one before. */
    actions(&fa);
    CHECK(posix_spawn_file_actions_addchdir_np(&fa, base) == 0);
    CHECK(posix_spawn_file_actions_addchdir_np(&fa, "sub") == 0);
    stdio(&fa);
    CHECK(pwd_in(&fa, out) == 0 && strcmp(out, sub) == 0);
    posix_spawn_file_actions_destroy(&fa);
    actions(&fa);
    CHECK(posix_spawn_file_actions_addfchdir_np(&fa, fd) == 0);
    CHECK(posix_spawn_file_actions_addchdir_np(&fa, "../sub") == 0);
    stdio(&fa);
    CHECK(pwd_in(&fa, out) == 0 && strcmp(out, sub) == 0);
    posix_spawn_file_actions_destroy(&fa);

    /* Destroyed actions leave nothing behind for the next ones. */
    actions(&fa);
    CHECK(posix_spawn_file_actions_addchdir_np(&fa, sub) == 0);
    posix_spawn_file_actions_destroy(&fa);
    actions(&fa);
    stdio(&fa);
    CHECK(pwd_in(&fa, out) == 0 && strcmp(out, start) == 0);
    posix_spawn_file_actions_destroy(&fa);

    /* The program path, a PATH search and later open actions resolve in the new directory. */
    actions(&fa);
    CHECK(posix_spawn_file_actions_addchdir_np(&fa, "/bin") == 0);
    {
        char *argv[] = {"./pwd", "-P", NULL};
        stdio(&fa);
        CHECK(run(&fa, NULL, 0, argv, out, sizeof out) == 0 && strcmp(out, "/bin") == 0);
    }
    posix_spawn_file_actions_destroy(&fa);
    actions(&fa);
    CHECK(posix_spawn_file_actions_addchdir_np(&fa, base) == 0);
    CHECK(posix_spawn_file_actions_addopen(&fa, 2, "made-here", O_WRONLY | O_CREAT | O_TRUNC, 0600) == 0);
    stdio(&fa);
    CHECK(pwd_in(&fa, out) == 0 && strcmp(out, base) == 0);
    posix_spawn_file_actions_destroy(&fa);
    {
        char made[PATH_MAX];
        struct stat sb;
        snprintf(made, sizeof made, "%s/made-here", base);
        CHECK(stat(made, &sb) == 0);
        unlink(made);
    }

    /* Errors: as the builder reports them, and as posix_spawn reports a chdir that fails. */
    actions(&fa);
    CHECK(posix_spawn_file_actions_addfchdir_np(&fa, -1) == EBADF);
    {
        char longpath[PATH_MAX + 1];
        memset(longpath, 'a', PATH_MAX);
        longpath[PATH_MAX] = 0;
        CHECK(posix_spawn_file_actions_addchdir_np(&fa, longpath) == ENAMETOOLONG);
    }
    CHECK(posix_spawn_file_actions_addchdir_np(&fa, "/nonexistent/recaulk") == 0);
    stdio(&fa);
    CHECK(pwd_in(&fa, out) == ENOENT);
    posix_spawn_file_actions_destroy(&fa);
    actions(&fa);
    {
        int file = open("/etc/hosts", O_RDONLY);
        CHECK(posix_spawn_file_actions_addfchdir_np(&fa, file) == 0);
        stdio(&fa);
        CHECK(pwd_in(&fa, out) == ENOTDIR);
        close(file);
    }
    posix_spawn_file_actions_destroy(&fa);
    parent_unmoved();

    /* An object that libSystem moves while growing keeps its chdir actions. */
    {
        void *first;
        int i, moved_object = 0;
        actions(&fa);
        CHECK(posix_spawn_file_actions_addchdir_np(&fa, sub) == 0);
        first = fa;
        for (i = 0; i < 64; i++) {
            void *before = fa;
            CHECK(posix_spawn_file_actions_addinherit_np(&fa, 2) == 0);
            if (fa != before) moved_object = 1;
        }
        stdio(&fa);
        CHECK(moved_object && fa != first);
        CHECK(pwd_in(&fa, out) == 0 && strcmp(out, sub) == 0);
        posix_spawn_file_actions_destroy(&fa);
    }

    /* Another thread never sees the parent's cwd move while children spawn in sub. */
    {
        pthread_t t;
        int i;
        CHECK(pthread_create(&t, NULL, watch, NULL) == 0);
        actions(&fa);
        CHECK(posix_spawn_file_actions_addchdir_np(&fa, sub) == 0);
        stdio(&fa);
        for (i = 0; i < 100; i++)
            CHECK(pwd_in(&fa, out) == 0 && strcmp(out, sub) == 0);
        posix_spawn_file_actions_destroy(&fa);
        watching = 0;
        pthread_join(t, NULL);
        CHECK(!moved);
    }

    /* POSIX_SPAWN_SETEXEC replaces this process, which must take the chdir too. */
    {
        int p[2], st;
        ssize_t n, got = 0;
        pid_t child;
        CHECK(pipe(p) == 0);
        child = fork();
        if (child == 0) {
            posix_spawnattr_t attr;
            char *argv[] = {"/bin/pwd", "-P", NULL};
            char now[PATH_MAX];
            close(p[0]);
            posix_spawnattr_init(&attr);
            posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC);
            posix_spawn_file_actions_init(&fa);
            posix_spawn_file_actions_addchdir_np(&fa, "/nonexistent/recaulk");
            if (posix_spawn(NULL, argv[0], &fa, &attr, argv, environ) != ENOENT) _exit(3);
            if (!getcwd(now, sizeof now) || strcmp(now, start) != 0) _exit(4);
            posix_spawn_file_actions_destroy(&fa);
            posix_spawn_file_actions_init(&fa);
            posix_spawn_file_actions_addchdir_np(&fa, other);
            posix_spawn_file_actions_adddup2(&fa, p[1], 1);
            posix_spawn(NULL, argv[0], &fa, &attr, argv, environ);
            _exit(5);
        }
        close(p[1]);
        while ((n = read(p[0], out + got, sizeof out - 1 - (size_t)got)) > 0) got += n;
        out[got] = 0;
        if (got && out[got - 1] == '\n') out[got - 1] = 0;
        close(p[0]);
        CHECK(waitpid(child, &st, 0) == child && WIFEXITED(st) && WEXITSTATUS(st) == 0);
        CHECK(strcmp(out, other) == 0);
    }

    close(fd);
    rmdir(sub);
    rmdir(other);
    rmdir(base);
    if (failures) return 1;
    puts("posix_spawn chdir: addchdir_np and addfchdir_np take effect in the child, and only there");
    return 0;
}
