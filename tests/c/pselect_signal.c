/* platform: 10.9's libc pselect sets the mask, calls select, then restores the mask, so a signal that
 * arrives in between runs its handler and the select sleeps on (Libc-997.90.3 gen/FreeBSD/pselect.c;
 * xnu has no pselect syscall before 10.11). Each case runs through all five of 10.9's pselect symbols
 * and prints "ok CASE VARIANT" or "FAIL CASE VARIANT: why". Linked against libc alone on 10.9, only
 * the cases a lost signal decides fail: that is the control. */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>
#include <pthread.h>

typedef int pselect_fn(int, fd_set *, fd_set *, fd_set *, const struct timespec *, const sigset_t *);
extern pselect_fn ps_plain __asm("_pselect");
extern pselect_fn ps_1050 __asm("_pselect$1050");
extern pselect_fn ps_extsn __asm("_pselect$DARWIN_EXTSN");
extern pselect_fn ps_extsn_nocancel __asm("_pselect$DARWIN_EXTSN$NOCANCEL");
extern pselect_fn ps_nocancel __asm("_pselect$NOCANCEL");

static const struct variant {
    const char *name;
    pselect_fn *fn;
    int limited; /* holds nfds to FD_SETSIZE */
} variants[] = {
    {"pselect", ps_plain, 0}, /* MEASURED 2026-11-06 on 10.9.5: the legacy symbol does not limit nfds */
    {"pselect$1050", ps_1050, 1},
    {"pselect$DARWIN_EXTSN", ps_extsn, 0},
    {"pselect$DARWIN_EXTSN$NOCANCEL", ps_extsn_nocancel, 0},
    {"pselect$NOCANCEL", ps_nocancel, 1},
};

static int failures;
static volatile sig_atomic_t handled;
static void on_chld(int sig) { (void)sig; handled = 1; }

static void fail(const char *c, const struct variant *v, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
static void fail(const char *c, const struct variant *v, const char *fmt, ...) {
    va_list ap;
    printf("FAIL %s %s: ", c, v->name);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    printf("\n");
    failures++;
}

static double now(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1e6;
}

/* SIGCHLD caught (or left default) and blocked; *open receives the mask that unblocks it. */
static void sigchld_blocked(int caught, sigset_t *open) {
    struct sigaction sa;
    sigset_t block;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = caught ? on_chld : SIG_DFL;
    sigaction(SIGCHLD, &sa, NULL);
    sigemptyset(&block);
    sigaddset(&block, SIGCHLD);
    sigprocmask(SIG_BLOCK, &block, open);
    sigdelset(open, SIGCHLD);
    handled = 0;
}

static void restore(void) {
    sigset_t none;
    struct sigaction sa;
    while (waitpid(-1, NULL, WNOHANG) > 0) {}
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = SIG_IGN; /* discard a SIGCHLD still pending, then put the default back */
    sigaction(SIGCHLD, &sa, NULL);
    sigemptyset(&none);
    sigprocmask(SIG_SETMASK, &none, NULL);
    sa.sa_handler = SIG_DFL;
    sigaction(SIGCHLD, &sa, NULL);
    while (waitpid(-1, NULL, WNOHANG) > 0) {}
}

static pid_t child_exiting_after(useconds_t us) {
    pid_t pid = fork();
    if (pid == 0) {
        if (us) usleep(us);
        _exit(0);
    }
    return pid;
}

static int sigchld_pending(void) {
    sigset_t p;
    sigpending(&p);
    return sigismember(&p, SIGCHLD);
}

/* The reproduction: SIGCHLD already pending, blocked, when pselect unblocks it. An atomic pselect
 * delivers it and returns EINTR at once; 10.9's libc runs the handler, then sleeps the whole timeout. */
static void pending_at_entry_returns_eintr_at_once(const struct variant *v) {
    sigset_t open;
    struct timespec ts = {5, 0};
    sigchld_blocked(1, &open);
    child_exiting_after(0);
    for (int i = 0; i < 500 && !sigchld_pending(); i++) usleep(10000);
    double t0 = now();
    int rc = v->fn(0, NULL, NULL, NULL, &ts, &open);
    int e = errno;
    double el = now() - t0;
    if (!(rc == -1 && e == EINTR && el < 1 && handled))
        fail(__func__, v, "rc=%d errno=%d elapsed=%.2fs handler=%d, want -1 EINTR at once with the handler run",
             rc, rc < 0 ? e : 0, el, (int)handled);
    else
        printf("ok %s %s\n", __func__, v->name);
    restore();
}

static void signal_during_wait_returns_eintr(const struct variant *v) {
    sigset_t open;
    struct timespec ts = {5, 0};
    sigchld_blocked(1, &open);
    child_exiting_after(200000);
    double t0 = now();
    int rc = v->fn(0, NULL, NULL, NULL, &ts, &open);
    int e = errno;
    double el = now() - t0;
    /* the handler has run, or runs as SIGCHLD is unblocked: the signal is not lost */
    sigset_t chld;
    sigemptyset(&chld);
    sigaddset(&chld, SIGCHLD);
    sigprocmask(SIG_UNBLOCK, &chld, NULL);
    if (!(rc == -1 && e == EINTR && el < 3 && handled))
        fail(__func__, v, "rc=%d errno=%d elapsed=%.2fs handler=%d, want -1 EINTR when the child exits",
             rc, rc < 0 ? e : 0, el, (int)handled);
    else
        printf("ok %s %s\n", __func__, v->name);
    restore();
}

static void readable_pipe_returns_one(const struct variant *v) {
    sigset_t open;
    int p[2];
    fd_set r;
    struct timespec ts = {5, 0};
    sigchld_blocked(1, &open);
    pipe(p);
    write(p[1], "x", 1);
    FD_ZERO(&r);
    FD_SET(p[0], &r);
    FD_SET(p[1], &r);
    int rc = v->fn(p[1] + 1, &r, NULL, NULL, &ts, &open);
    int only = 1;
    for (int fd = 0; fd <= p[1]; fd++)
        if (fd != p[0] && FD_ISSET(fd, &r)) only = 0;
    if (!(rc == 1 && FD_ISSET(p[0], &r) && only))
        fail(__func__, v, "rc=%d errno=%d read-ready=%d other-bits=%d, want 1 with only the pipe's bit",
             rc, rc < 0 ? errno : 0, FD_ISSET(p[0], &r) != 0, !only);
    else
        printf("ok %s %s\n", __func__, v->name);
    close(p[0]);
    close(p[1]);
    restore();
}

/* A readable descriptor and a signal at once: either answer is atomic, but the caller's set never
 * holds a bit it did not ask about. The signal is pending before the call, so Recaulk answers EINTR from
 * its first check; the branch where a descriptor and a post end the same select is read, not run. */
static void ready_fd_and_signal(const struct variant *v) {
    sigset_t open;
    int p[2];
    fd_set r;
    struct timespec ts = {5, 0};
    sigchld_blocked(1, &open);
    pipe(p);
    write(p[1], "x", 1);
    child_exiting_after(0);
    for (int i = 0; i < 500 && !sigchld_pending(); i++) usleep(10000);
    FD_ZERO(&r);
    FD_SET(p[0], &r);
    int rc = v->fn(p[0] + 1, &r, NULL, NULL, &ts, &open);
    int e = errno;
    int stray = 0;
    for (int fd = 0; fd < p[0]; fd++)
        if (FD_ISSET(fd, &r)) stray = 1;
    if (!((rc == -1 && e == EINTR) || (rc == 1 && FD_ISSET(p[0], &r))) || stray)
        fail(__func__, v, "rc=%d errno=%d stray-bits=%d, want EINTR or 1 with only the pipe's bit",
             rc, rc < 0 ? e : 0, stray);
    else
        printf("ok %s %s\n", __func__, v->name);
    close(p[0]);
    close(p[1]);
    restore();
}

/* A SIGCHLD left at its default action is discarded, so it never interrupts a wait. */
static void default_disposition_no_eintr(const struct variant *v) {
    sigset_t open;
    struct timespec ts = {1, 0};
    sigchld_blocked(0, &open);
    child_exiting_after(200000);
    double t0 = now();
    int rc = v->fn(0, NULL, NULL, NULL, &ts, &open);
    double el = now() - t0;
    if (!(rc == 0 && el > 0.9))
        fail(__func__, v, "rc=%d errno=%d elapsed=%.2fs, want 0 after the whole 1 s", rc, rc < 0 ? errno : 0, el);
    else
        printf("ok %s %s\n", __func__, v->name);
    restore();
}

static void timeout_honoured(const struct variant *v) {
    sigset_t open;
    struct timespec ts = {0, 300000000};
    sigchld_blocked(1, &open);
    double t0 = now();
    int rc = v->fn(0, NULL, NULL, NULL, &ts, &open);
    double el = now() - t0;
    if (!(rc == 0 && el >= 0.25 && el < 1.5))
        fail(__func__, v, "rc=%d elapsed=%.2fs, want 0 after about 0.3 s", rc, el);
    else
        printf("ok %s %s\n", __func__, v->name);
    restore();
}

static void null_mask_is_select(const struct variant *v) {
    int p[2];
    fd_set r;
    struct timespec ts = {5, 0};
    pipe(p);
    write(p[1], "x", 1);
    FD_ZERO(&r);
    FD_SET(p[0], &r);
    int rc = v->fn(p[0] + 1, &r, NULL, NULL, &ts, NULL);
    if (!(rc == 1 && FD_ISSET(p[0], &r)))
        fail(__func__, v, "rc=%d errno=%d, want 1 with the pipe's bit", rc, rc < 0 ? errno : 0);
    else
        printf("ok %s %s\n", __func__, v->name);
    close(p[0]);
    close(p[1]);
}

static void nfds_over_fd_setsize_einval(const struct variant *v) {
    if (!v->limited) return;
    sigset_t open;
    static fd_set r[2];
    struct timespec ts = {0, 0};
    sigchld_blocked(1, &open);
    int rc = v->fn(FD_SETSIZE + 1, r, NULL, NULL, &ts, &open);
    int e = errno;
    if (!(rc == -1 && e == EINVAL))
        fail(__func__, v, "rc=%d errno=%d, want -1 EINVAL", rc, rc < 0 ? e : 0);
    else
        printf("ok %s %s\n", __func__, v->name);
    restore();
}

static void bad_nsec_einval(const struct variant *v) {
    sigset_t open;
    struct timespec ts = {0, 1000000000};
    sigchld_blocked(1, &open);
    int rc = v->fn(0, NULL, NULL, NULL, &ts, &open);
    int e = errno;
    if (!(rc == -1 && e == EINVAL))
        fail(__func__, v, "rc=%d errno=%d, want -1 EINVAL", rc, rc < 0 ? e : 0);
    else
        printf("ok %s %s\n", __func__, v->name);
    restore();
}

/* The caller's sets are only as wide as its nfds: nothing past them is read or written, however high a
 * descriptor pselect itself uses. Each set here is one 32-bit word, guarded on both sides. */
static void pselect_never_touches_past_nfds(const struct variant *v) {
    sigset_t open;
    int p[2];
    struct timespec ts = {5, 0};
    unsigned char *buf[3];
    sigchld_blocked(1, &open);
    pipe(p);
    write(p[1], "x", 1);
    if (p[1] >= 32) { fail(__func__, v, "the pipe is at fd %d, past one word", p[1]); restore(); return; }
    for (int i = 0; i < 3; i++) {
        buf[i] = malloc(4 + 4 + 64);
        memset(buf[i], 0xa5, 4 + 4 + 64);
        memset(buf[i] + 4, 0, 4);
    }
    FD_SET(p[0], (fd_set *)(buf[0] + 4));
    int rc = v->fn(p[1] + 1, (fd_set *)(buf[0] + 4), (fd_set *)(buf[1] + 4), (fd_set *)(buf[2] + 4), &ts, &open);
    int guarded = 1;
    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 4 + 4 + 64; j++)
            if ((j < 4 || j >= 8) && buf[i][j] != 0xa5) guarded = 0;
    if (!(rc == 1 && FD_ISSET(p[0], (fd_set *)(buf[0] + 4)) && guarded))
        fail(__func__, v, "rc=%d errno=%d guards-intact=%d, want 1 and nothing past nfds touched",
             rc, rc < 0 ? errno : 0, guarded);
    else
        printf("ok %s %s\n", __func__, v->name);
    for (int i = 0; i < 3; i++) free(buf[i]);
    close(p[0]);
    close(p[1]);
    restore();
}

/* A wait that watched no signal leaves nothing behind to end the next wait that does. */
static void unwatched_wait_leaves_no_stale_interrupt(const struct variant *v) {
    sigset_t open;
    struct timespec ts = {0, 500000000}, short_ts = {0, 300000000};
    sigchld_blocked(0, &open);
    child_exiting_after(100000);
    v->fn(0, NULL, NULL, NULL, &ts, &open);
    restore();
    sigchld_blocked(1, &open);
    double t0 = now();
    int rc = v->fn(0, NULL, NULL, NULL, &short_ts, &open);
    double el = now() - t0;
    if (!(rc == 0 && el >= 0.25))
        fail(__func__, v, "rc=%d errno=%d elapsed=%.2fs, want 0 after about 0.3 s", rc, rc < 0 ? errno : 0, el);
    else
        printf("ok %s %s\n", __func__, v->name);
    restore();
}

/* A forked child, which inherits no kqueue, is woken by a signal during its wait as its parent is. */
static void fork_child_waits_race_free(const struct variant *v) {
    fflush(stdout);
    pid_t pid = fork();
    if (pid == 0) {
        int before = failures;
        signal_during_wait_returns_eintr(v);
        _exit(failures != before);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) fail(__func__, v, "the child's wait failed (status %d)", st);
    else printf("ok %s %s\n", __func__, v->name);
}

static void *thread_case(void *arg) {
    int before = failures;
    signal_during_wait_returns_eintr(arg);
    return (void *)(intptr_t)(failures != before);
}

/* A thread's first wait registers its own kqueue and is woken by a signal during it. Every other thread
 * blocks SIGCHLD, so 10.9 routes the child's to the one thread the wait unblocks it in. */
static void new_thread_waits_race_free(const struct variant *v) {
    pthread_t t;
    void *bad = NULL;
    sigset_t all, old;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, &old); /* the new thread alone takes SIGCHLD while it waits */
    pthread_create(&t, NULL, thread_case, (void *)v);
    pthread_join(t, &bad);
    pthread_sigmask(SIG_SETMASK, &old, NULL);
    restore();
    if (bad) fail(__func__, v, "the new thread's wait failed");
    else printf("ok %s %s\n", __func__, v->name);
}

/* A program may close every descriptor it did not open itself, as sshd does with closefrom(3), and then
 * open another at the number pselect's kqueue had: pselect still waits, and wakes, as it should. */
static void kqueue_number_taken_over(const struct variant *v, int reopen, const char *name) {
    fflush(stdout);
    pid_t pid = fork();
    if (pid == 0) {
        for (int fd = 3; fd < 256; fd++) close(fd);
        if (reopen) open("/dev/null", O_RDONLY);
        int before = failures;
        signal_during_wait_returns_eintr(v);
        timeout_honoured(v);
        _exit(failures != before);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) fail(name, v, "a wait after the descriptors were closed failed (status %d)", st);
    else printf("ok %s %s\n", name, v->name);
}
static void kqueue_number_reused_by_dev_null(const struct variant *v) {
    kqueue_number_taken_over(v, 1, __func__);
}
static void kqueue_number_closed(const struct variant *v) {
    kqueue_number_taken_over(v, 0, __func__);
}

static void *high_kqueue_thread(void *arg) {
    int before = failures;
    pselect_never_touches_past_nfds(arg);
    return (void *)(intptr_t)(failures != before);
}

/* A thread whose kqueue lands far past the caller's one-word sets: nothing past nfds is touched. */
static void high_kqueue_never_touches_past_nfds(const struct variant *v) {
    int held[64], n = 0, fd;
    while ((fd = open("/dev/null", O_RDONLY)) >= 0 && fd < 64 && n < 64) held[n++] = fd;
    if (fd >= 0) close(fd);
    /* the pipe the case makes must stay inside one word: free two low numbers for it */
    close(held[0]);
    close(held[1]);
    pthread_t t;
    void *bad = NULL;
    sigset_t all, old;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, &old);
    pthread_create(&t, NULL, high_kqueue_thread, (void *)v);
    pthread_join(t, &bad);
    pthread_sigmask(SIG_SETMASK, &old, NULL);
    for (int i = 2; i < n; i++) close(held[i]);
    restore();
    if (bad) fail(__func__, v, "the thread's wait failed");
    else printf("ok %s %s\n", __func__, v->name);
}

int main(void) {
    void (*cases[])(const struct variant *) = {
        pending_at_entry_returns_eintr_at_once,
        signal_during_wait_returns_eintr,
        readable_pipe_returns_one,
        ready_fd_and_signal,
        default_disposition_no_eintr,
        timeout_honoured,
        null_mask_is_select,
        nfds_over_fd_setsize_einval,
        bad_nsec_einval,
        pselect_never_touches_past_nfds,
        unwatched_wait_leaves_no_stale_interrupt,
        fork_child_waits_race_free,
        new_thread_waits_race_free,
        kqueue_number_reused_by_dev_null,
        kqueue_number_closed,
        high_kqueue_never_touches_past_nfds,
    };
    setvbuf(stdout, NULL, _IOLBF, 0);
    for (size_t c = 0; c < sizeof cases / sizeof cases[0]; c++)
        for (size_t i = 0; i < sizeof variants / sizeof variants[0]; i++)
            cases[c](&variants[i]);
    printf(failures ? "pselect_signal: %d failed\n" : "pselect_signal: all passed\n", failures);
    return failures != 0;
}
