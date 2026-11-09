/*
 * close and dup2 that never hang on a socket another thread is entering a read, accept or receive on.
 *
 * Closing or replacing a descriptor some thread is using runs xnu's fileproc_drain: it calls fo_drain (for a
 * socket, soo_drain marks it SS_DRAINING and wakes its sleepers), then sleeps, with no timeout, until the
 * descriptor's last user leaves. A thread that took the descriptor but had not yet slept misses that wakeup:
 * sbwait checks SS_DRAINING only after it wakes (xnu-2422, 10.9, to xnu-2782, 10.10; xnu-3789, 10.12,
 * checks before sleeping), and accept does so even in xnu-7195, macOS 11. The drain sleep then lasts until some
 * other descriptor in the process is released (fp_drop wakes it at iocount zero), which may be never: java
 * (jdk-25) measured closes blocked for seconds, and MEASURED 2026-11-09 on 10.9.5, a reader entering read,
 * accept or recv as another thread dup2'd over its socket hung every run of 3000 closes (tests/socket-close-race.sh).
 *
 * So while a close or dup2 of a socket is outstanding, a helper thread releases a descriptor of its own every
 * 200 microseconds, after the first millisecond: it creates a kqueue and closes it. Each release wakes the
 * drain, which runs soo_drain again, and so wakes the reader that slept late; it leaves, and the close
 * completes. MEASURED the same day: 0 of 15 runs hung with the helper, 15 of 15 without. It ticks until the
 * close returns, not for a fixed time, and after a second slows to every 10 ms, so a close that blocks for
 * another reason (SO_LINGER) costs little. A descriptor that is not a socket costs one fstat and nothing else.
 *
 * The helper starts at the first socket close: a close in a signal handler can be that one, and starting a
 * thread is not async-signal-safe. It waits on a kqueue for an EVFILT_USER trigger; each trigger doubles as the
 * check that the kqueue is still the helper's, since a program may close every descriptor it did not open, and
 * a forked child inherits no kqueue, so either one starts a new helper. Not 10.9-only: accept's window is still
 * open in macOS 11's xnu.
 *
 * close, close$NOCANCEL and dup2 are 10.9 exports, so here they are weak and hidden
 * (build/image-local-shadows.txt; README "Closing a socket"): they bind only inside the image that links
 * librecaulk.a, and yield to the public ones src/overrides/socket_close_export.c gives libRecaulkSystem.dylib.
 * No header renames them: a macro named close would rename C++'s stream.close(), so a program reaches them by
 * link order, as clang22's configuration gives it (librecaulk.a before libSystem).
 */
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/event.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

int __recaulk_close(int fd);
int __recaulk_close_nocancel(int fd);
int __recaulk_dup2(int from, int to);

/* platform: 10.9's close, close$NOCANCEL and dup2 are bare system call stubs (libsystem_kernel), and this file
 * defines their names, so it makes the same calls itself. */
static int sys_close(int fd) { return syscall(SYS_close, fd); }
static int sys_close_nocancel(int fd) { return syscall(SYS_close_nocancel, fd); }
static int sys_dup2(int from, int to) { return syscall(SYS_dup2, from, to); }

static int pending;        /* closes and dup2s of a socket under way */
static int helper_kq = -1; /* the kqueue the helper waits on */
static pthread_mutex_t start_lock = PTHREAD_MUTEX_INITIALIZER;
#define TRIGGER ((uintptr_t)&pending)

static void pause_for(long ns) {
    struct timespec t = {0, ns};
    nanosleep(&t, NULL);
}

static void *helper(void *arg) {
    int kq = (int)(intptr_t)arg;
    for (;;) {
        struct kevent ev;
        int n = kevent(kq, NULL, 0, &ev, 1, NULL);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) return NULL; /* its kqueue is gone; the next socket close starts another helper */
        pause_for(1000000);
        for (unsigned ticks = 0; __atomic_load_n(&pending, __ATOMIC_ACQUIRE) > 0; ticks++) {
            int k = kqueue();
            if (k >= 0) sys_close_nocancel(k);
            pause_for(ticks < 5000 ? 200000 : 10000000);
        }
    }
}

/* Wake the helper; 0 if this kqueue is still the helper's and took the trigger. */
static int trigger(int kq) {
    struct kevent change, out;
    struct timespec zero = {0, 0};
    if (kq < 0) return -1;
    EV_SET(&change, TRIGGER, EVFILT_USER, EV_RECEIPT, NOTE_TRIGGER, 0, NULL);
    return kevent(kq, &change, 1, &out, 1, &zero) == 1 && (out.flags & EV_ERROR) && out.data == 0 ? 0 : -1;
}

static void start_helper(void) {
    pthread_mutex_lock(&start_lock);
    int kq = __atomic_load_n(&helper_kq, __ATOMIC_ACQUIRE);
    if (trigger(kq) != 0) {
        int saved = errno;
        struct kevent add;
        pthread_attr_t attr;
        pthread_t t;
        kq = kqueue();
        EV_SET(&add, TRIGGER, EVFILT_USER, EV_ADD | EV_CLEAR, 0, 0, NULL);
        if (kq >= 0 && kevent(kq, &add, 1, NULL, 0, NULL) == 0 && pthread_attr_init(&attr) == 0) {
            pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
            if (pthread_create(&t, &attr, helper, (void *)(intptr_t)kq) == 0) {
                __atomic_store_n(&helper_kq, kq, __ATOMIC_RELEASE);
                trigger(kq);
                kq = -1;
            }
            pthread_attr_destroy(&attr);
        }
        if (kq >= 0) sys_close_nocancel(kq);
        errno = saved;
    }
    pthread_mutex_unlock(&start_lock);
}

static int is_socket(int fd) {
    struct stat st;
    int saved = errno, sock = fstat(fd, &st) == 0 && S_ISSOCK(st.st_mode);
    errno = saved;
    return sock;
}

static void begin(void) {
    if (__atomic_fetch_add(&pending, 1, __ATOMIC_ACQ_REL) == 0) {
        int saved = errno;
        if (trigger(__atomic_load_n(&helper_kq, __ATOMIC_ACQUIRE)) != 0) start_helper();
        errno = saved;
    }
}
static void end(void) { __atomic_fetch_sub(&pending, 1, __ATOMIC_ACQ_REL); }

int __recaulk_close(int fd) {
    if (!is_socket(fd)) return sys_close(fd);
    begin();
    int rv = sys_close(fd);
    end();
    return rv;
}

int __recaulk_close_nocancel(int fd) {
    if (!is_socket(fd)) return sys_close_nocancel(fd);
    begin();
    int rv = sys_close_nocancel(fd);
    end();
    return rv;
}

int __recaulk_dup2(int from, int to) {
    if (from == to || !is_socket(to)) return sys_dup2(from, to);
    begin();
    int rv = sys_dup2(from, to);
    end();
    return rv;
}

__attribute__((weak, visibility("hidden"))) int recaulk_close(int) __asm("_close");
int recaulk_close(int fd) { return __recaulk_close(fd); }
__attribute__((weak, visibility("hidden"))) int recaulk_close_nocancel(int) __asm("_close$NOCANCEL");
int recaulk_close_nocancel(int fd) { return __recaulk_close_nocancel(fd); }
__attribute__((weak, visibility("hidden"))) int recaulk_dup2(int, int) __asm("_dup2");
int recaulk_dup2(int from, int to) { return __recaulk_dup2(from, to); }
