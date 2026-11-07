/*
 * pselect for 10.9 that never loses a signal. 10.9's libc pselect sets the signal mask, calls select,
 * then restores the mask, as three separate steps (Libc-997.90.3 gen/FreeBSD/pselect.c; xnu has no
 * pselect syscall before 10.11's xnu-3248). A signal the mask unblocks that is already pending, or
 * arrives before select starts, runs its handler first, and select then sleeps on with nothing to
 * wake it: sshd-session so missed its child's SIGCHLD and never reaped it (mavericks-vm run
 * 42299349324).
 *
 * xnu posts a process-directed signal to its kqueue EVFILT_SIGNAL knotes (xnu-2422 bsd/kern/kern_sig.c,
 * psignal_internal, before any mask or ignore check). A kqueue registered for every catchable signal so
 * records each post from then on. One is registered per thread: a forked child's at the fork, the main
 * thread's as libRecaulkSystem.dylib loads, and any other thread's (and, linked from librecaulk.a, the
 * main thread's) at its first pselect. Registered any later, as each
 * call, a post already under way when the knote attached would reach neither the knote nor
 * sigpending (it sets the thread's pending set only after its proc_knote): MEASURED 2026-11-06, 5 lost
 * in 3000 waits that way, against libc's 81.
 *
 * Each call that unblocks a signal with a handler first drains its thread's kqueue: a post of such a
 * signal since the thread's last wait, or one pending now, ends the call with EINTR, the handler run.
 * Otherwise the kqueue joins the read set of the select the mask brackets, so a post at any point after
 * the drain ends the wait. Posts of other signals are drained and the wait goes on. The caller's sets
 * are copied into private ones wide enough for the kqueue, so nothing past the caller's nfds is read or
 * written. On Darwin 15 (10.11) and later, the system's pselect is atomic and runs instead.
 *
 * Limits (README "Waiting with pselect"): a signal handled outside any wait can end the thread's next
 * wait at once with EINTR; a thread-directed signal (pthread_kill) posts no knote, so it is no better
 * covered than by 10.9's own; a process-directed signal another thread handles can end the wait with
 * EINTR; and a post under way as a new thread's kqueue is first registered is not seen.
 *
 * pselect's five 10.9 symbols are 10.9 exports, so here they are weak and hidden
 * (build/image-local-shadows.txt; README "Fixes to functions 10.9 has"): they bind only inside the
 * image that links librecaulk.a, and yield to the public ones src/overrides/pselect_export.c gives
 * libRecaulkSystem.dylib.
 */
#include <dlfcn.h>
#include <fcntl.h>
#include <stdint.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/select.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <unistd.h>
#include <pthread.h>

#define RECAULK_PSELECT_EXTSN 1    /* $DARWIN_EXTSN: nfds unlimited */
#define RECAULK_PSELECT_NOCANCEL 2 /* $NOCANCEL: not a cancellation point */
#define RECAULK_PSELECT_LEGACY 4   /* plain _pselect: nfds unlimited, as 10.9's is */

typedef int pselect_fn(int, fd_set *, fd_set *, fd_set *, const struct timespec *, const sigset_t *);
typedef int select_fn(int, fd_set *, fd_set *, fd_set *, struct timeval *);
extern select_fn select_unlimited __asm("_select$DARWIN_EXTSN");
extern select_fn select_unlimited_nocancel __asm("_select$DARWIN_EXTSN$NOCANCEL");

int __recaulk_pselect(int variant, int nfds, fd_set *r, fd_set *w, fd_set *e,
                      const struct timespec *timeout, const sigset_t *mask);

/* platform: Darwin 15 (10.11) is the first with a pselect syscall; sysctl by MIB allocates nothing */
static int atomic_pselect(void) {
    static int known = -1;
    int k = __atomic_load_n(&known, __ATOMIC_RELAXED);
    if (k < 0) {
        int mib[2] = {CTL_KERN, KERN_OSRELEASE}, major = 0;
        char rel[32];
        size_t n = sizeof rel;
        if (sysctl(mib, 2, rel, &n, 0, 0) == 0)
            for (const char *p = rel; p < rel + n && *p >= '0' && *p <= '9'; p++)
                major = major * 10 + (*p - '0');
        k = major >= 15;
        __atomic_store_n(&known, k, __ATOMIC_RELAXED);
    }
    return k;
}

static pselect_fn *system_pselect(int variant) {
    static pselect_fn *found[8];
    pselect_fn *f = __atomic_load_n(&found[variant], __ATOMIC_RELAXED);
    if (!f) {
        const char *name = (variant & RECAULK_PSELECT_LEGACY) ? "pselect"
                         : (variant & RECAULK_PSELECT_EXTSN)
                             ? ((variant & RECAULK_PSELECT_NOCANCEL) ? "pselect$DARWIN_EXTSN$NOCANCEL"
                                                                     : "pselect$DARWIN_EXTSN")
                             : ((variant & RECAULK_PSELECT_NOCANCEL) ? "pselect$NOCANCEL" : "pselect$1050");
        f = (pselect_fn *)dlsym(RTLD_NEXT, name);
        __atomic_store_n(&found[variant], f, __ATOMIC_RELAXED);
    }
    return f;
}

static int caught(int sig) {
    struct sigaction sa;
    if (sigaction(sig, NULL, &sa) != 0) return 0;
    if (sa.sa_flags & SA_SIGINFO) return sa.sa_sigaction != NULL;
    return sa.sa_handler != SIG_DFL && sa.sa_handler != SIG_IGN;
}

/* Copy the caller's first nfds bits into a private set of the given words, clearing the rest. */
static void copy_in(fd_mask *to, const fd_set *from, int nfds, size_t words) {
    memset(to, 0, words * sizeof(fd_mask));
    if (!from) return;
    size_t full = (size_t)nfds / NFDBITS, part = (size_t)nfds % NFDBITS;
    memcpy(to, from->fds_bits, full * sizeof(fd_mask));
    if (part) to[full] = from->fds_bits[full] & (fd_mask)((1u << part) - 1);
}

/* Write back exactly the caller's words: the bits below nfds as select set them, the rest clear. */
static void copy_out(fd_set *to, const fd_mask *from, int nfds) {
    if (!to) return;
    size_t full = (size_t)nfds / NFDBITS, part = (size_t)nfds % NFDBITS;
    memcpy(to->fds_bits, from, full * sizeof(fd_mask));
    if (part) to->fds_bits[full] = from[full] & (fd_mask)((1u << part) - 1);
}

static pthread_key_t kqueue_key;
static pthread_once_t kqueue_key_once = PTHREAD_ONCE_INIT;

/* platform: a program may close every descriptor it did not open (sshd's closefrom(3)) and open another
 * at the number this kqueue had. So each of this file's kqueues carries an EVFILT_USER marker no other
 * kqueue has, keyed by this variable's address, and a number is used, or closed, only while it still
 * answers for that marker. */
#define MARKER ((uintptr_t)&kqueue_key)

static int ours(int kq) {
    struct kevent probe, out;
    struct timespec zero = {0, 0};
    EV_SET(&probe, MARKER, EVFILT_USER, EV_RECEIPT, NOTE_FFNOP, 0, NULL);
    return kq >= 0 && kevent(kq, &probe, 1, &out, 1, &zero) == 1 && (out.flags & EV_ERROR) && out.data == 0;
}

static void close_kqueue(void *v) {
    int kq = (int)(intptr_t)v - 1;
    if (ours(kq)) close(kq);
}
static void fork_child_kqueue(void);
static void make_kqueue_key(void) {
    pthread_key_create(&kqueue_key, close_kqueue);
    pthread_atfork(NULL, NULL, fork_child_kqueue);
}

/* This thread's kqueue if it is still the one registered here, or -1. */
static int current_kqueue(void) {
    pthread_once(&kqueue_key_once, make_kqueue_key);
    int kq = (int)(intptr_t)pthread_getspecific(kqueue_key) - 1;
    if (kq < 0) return -1;
    if (ours(kq)) return kq;
    pthread_setspecific(kqueue_key, NULL); /* the number names something else now: forget it, never close it */
    return -1;
}

/* This thread's kqueue, registered for every catchable signal, created on first use. */
static int thread_kqueue(void) {
    int kq = current_kqueue();
    if (kq >= 0) return kq;
    struct kevent ev[NSIG + 1];
    int n = 0;
    for (int sig = 1; sig < NSIG; sig++)
        if (sig != SIGKILL && sig != SIGSTOP) EV_SET(&ev[n++], sig, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
    EV_SET(&ev[n++], MARKER, EVFILT_USER, EV_ADD | EV_CLEAR, 0, 0, NULL);
    kq = kqueue();
    if (kq < 0) return -1;
    /* platform: never on 0-2, which a program that starts with them closed may open again as stdio */
    if (kq < 3) {
        int high = fcntl(kq, F_DUPFD, 3);
        close(kq);
        if (high < 0) return -1;
        kq = high;
    }
    if (fcntl(kq, F_SETFD, FD_CLOEXEC) < 0 || kevent(kq, ev, n, NULL, 0, NULL) < 0) {
        int err = errno;
        close(kq);
        errno = err;
        return -1;
    }
    pthread_setspecific(kqueue_key, (void *)(intptr_t)(kq + 1));
    return kq;
}

/* Forget what this thread's kqueue saw during a wait that watched none of it, so it does not end the
 * next wait that does. */
static void drain_thread_kqueue(void) {
    int kq = current_kqueue();
    struct timespec zero = {0, 0};
    struct kevent evs[32];
    if (kq >= 0)
        while (kevent(kq, NULL, 0, evs, 32, &zero) > 0) {}
}

/* platform: a fork's child inherits no kqueue, and its descriptor number may now name something else:
 * forget it without closing it, and register the child's own at once. */
static void fork_child_kqueue(void) {
    pthread_setspecific(kqueue_key, NULL);
    thread_kqueue();
}

/* spec: tests/rule-backfills-add-only.sh -- librecaulk.a has no constructor, so a program linking it
 * registers its main thread's kqueue at that thread's first wait; libRecaulkSystem.dylib's constructor
 * (src/overrides/pselect_export.c) registers it as the image loads. */
void __recaulk_pselect_early(void) {
    if (!atomic_pselect()) thread_kqueue();
}

struct masked {
    const sigset_t *saved;
};
static void unmask_on_cancel(void *m) { pthread_sigmask(SIG_SETMASK, ((struct masked *)m)->saved, NULL); }

/* 10.9's own pselect: mask, select, unmask. Exact where no caught signal is unblocked; otherwise the
 * fallback when no kqueue can be had, racy as 10.9's but never failing where it would not. */
static int plain(select_fn *sel, int nfds, fd_set *r, fd_set *w, fd_set *e, struct timeval *tvp,
                 const sigset_t *mask) {
    sigset_t saved;
    struct masked m = {&saved};
    int rv, err;
    if (mask) pthread_sigmask(SIG_SETMASK, mask, &saved);
    else pthread_sigmask(SIG_BLOCK, NULL, &saved);
    pthread_cleanup_push(unmask_on_cancel, &m);
    rv = sel(nfds, r, w, e, tvp);
    err = errno;
    pthread_cleanup_pop(0);
    if (mask) pthread_sigmask(SIG_SETMASK, &saved, NULL);
    errno = err;
    return rv;
}

int __recaulk_pselect(int variant, int nfds, fd_set *r, fd_set *w, fd_set *e,
                      const struct timespec *timeout, const sigset_t *mask) {
    if (atomic_pselect()) {
        pselect_fn *f = system_pselect(variant);
        if (!f) { errno = ENOSYS; return -1; }
        return f(nfds, r, w, e, timeout, mask);
    }
    select_fn *sel = (variant & RECAULK_PSELECT_NOCANCEL) ? select_unlimited_nocancel : select_unlimited;
    if (nfds < 0 || (!(variant & (RECAULK_PSELECT_EXTSN | RECAULK_PSELECT_LEGACY)) && nfds > FD_SETSIZE)) {
        errno = EINVAL;
        return -1;
    }
    struct timeval tv, *tvp = NULL;
    if (timeout) {
        if (timeout->tv_sec < 0 || timeout->tv_nsec < 0 || timeout->tv_nsec >= 1000000000L) {
            errno = EINVAL;
            return -1;
        }
        tv.tv_sec = timeout->tv_sec;
        tv.tv_usec = (__darwin_suseconds_t)(timeout->tv_nsec / 1000);
        tvp = &tv;
    }

    sigset_t current, watched, pending, saved;
    int any = 0;
    sigemptyset(&watched);
    if (mask) {
        pthread_sigmask(SIG_BLOCK, NULL, &current);
        for (int sig = 1; sig < NSIG; sig++)
            if (sig != SIGKILL && sig != SIGSTOP && sigismember(&current, sig) && !sigismember(mask, sig)
                && caught(sig)) {
                sigaddset(&watched, sig);
                any = 1;
            }
    }
    if (!any) {
        /* Nothing a handler would see can be lost: mask, select, unmask is pselect here. */
        int rv = plain(sel, nfds, r, w, e, tvp, mask);
        int err = errno;
        drain_thread_kqueue();
        errno = err;
        return rv;
    }

    int kq = thread_kqueue();
    if (kq < 0) return plain(sel, nfds, r, w, e, tvp, mask);
    struct timespec zero = {0, 0};
    struct kevent evs[32];
    int interrupted = 0, n;
    /* A watched signal posted since this thread's last wait, or pending now: deliver it, report it. */
    while ((n = kevent(kq, NULL, 0, evs, 32, &zero)) > 0)
        for (int i = 0; i < n; i++)
            if (sigismember(&watched, (int)evs[i].ident)) interrupted = 1;
    sigpending(&pending);
    for (int sig = 1; sig < NSIG; sig++)
        if (sigismember(&watched, sig) && sigismember(&pending, sig)) interrupted = 1;
    if (interrupted) {
        pthread_sigmask(SIG_SETMASK, mask, &saved);
        pthread_sigmask(SIG_SETMASK, &saved, NULL);
        errno = EINTR;
        return -1;
    }

    int width = nfds > kq + 1 ? nfds : kq + 1;
    size_t words = ((size_t)width + NFDBITS - 1) / NFDBITS;
    /* platform: pselect is async-signal-safe and a cancellation point, so the common width allocates
     * nothing; only a set wider than FD_SETSIZE needs the heap */
    fd_set stack_sets[3];
    fd_mask *sets = words <= sizeof stack_sets[0].fds_bits / sizeof(fd_mask) ? (fd_mask *)stack_sets
                                                                            : calloc(3 * words, sizeof(fd_mask));
    if (!sets) return plain(sel, nfds, r, w, e, tvp, mask);
    fd_mask *pr = sets, *pw = sets + words, *pe = sets + 2 * words;
    struct timeval end;
    if (tvp) {
        gettimeofday(&end, NULL);
        timeradd(&end, tvp, &end);
    }
    int rv, err;
    for (;;) {
        copy_in(pr, r, nfds, words);
        copy_in(pw, w, nfds, words);
        copy_in(pe, e, nfds, words);
        pr[kq / NFDBITS] |= (fd_mask)(1u << (kq % NFDBITS));
        struct masked m = {&saved};
        pthread_sigmask(SIG_SETMASK, mask, &saved);
        pthread_cleanup_push(unmask_on_cancel, &m);
        rv = sel(width, (fd_set *)pr, w ? (fd_set *)pw : NULL, e ? (fd_set *)pe : NULL, tvp);
        err = errno;
        pthread_cleanup_pop(0);
        pthread_sigmask(SIG_SETMASK, &saved, NULL);
        int posted = 0, watched_posted = 0;
        if (rv > 0 && (pr[kq / NFDBITS] & (fd_mask)(1u << (kq % NFDBITS)))) {
            pr[kq / NFDBITS] &= ~(fd_mask)(1u << (kq % NFDBITS));
            rv--;
            posted = 1;
        }
        if (posted || (rv < 0 && err == EINTR)) {
            /* Drain what this wait saw, so it does not end the next one too. */
            while ((n = kevent(kq, NULL, 0, evs, 32, &zero)) > 0)
                for (int i = 0; i < n; i++)
                    if (sigismember(&watched, (int)evs[i].ident)) watched_posted = 1;
        }
        if (watched_posted) {
            /* The post may have landed after the mask went back: deliver it now if it is pending. */
            sigpending(&pending);
            for (int sig = 1; sig < NSIG; sig++)
                if (sigismember(&watched, sig) && sigismember(&pending, sig)) {
                    sigset_t again;
                    pthread_sigmask(SIG_SETMASK, mask, &again);
                    pthread_sigmask(SIG_SETMASK, &again, NULL);
                    break;
                }
        }
        if (rv != 0 || !posted) break;
        if (watched_posted) {
            rv = -1;
            err = EINTR;
            break;
        }
        /* Only signals this call does not watch were posted: wait on for what is left of the timeout. */
        if (tvp) {
            struct timeval now;
            gettimeofday(&now, NULL);
            if (!timercmp(&now, &end, <)) break;
            timersub(&end, &now, tvp);
        }
    }
    if (rv >= 0) {
        copy_out(r, pr, nfds);
        copy_out(w, pw, nfds);
        copy_out(e, pe, nfds);
    }
    if (sets != (fd_mask *)stack_sets) free(sets);
    errno = err;
    return rv;
}

#define SHADOW(name, symbol, variant)                                                                \
    __attribute__((weak, visibility("hidden"))) int name(int, fd_set *, fd_set *, fd_set *,            \
                                                         const struct timespec *, const sigset_t *)     \
        __asm(symbol);                                                                                 \
    int name(int nfds, fd_set *r, fd_set *w, fd_set *e, const struct timespec *t, const sigset_t *m) { \
        return __recaulk_pselect(variant, nfds, r, w, e, t, m);                                        \
    }
SHADOW(recaulk_pselect_legacy, "_pselect", RECAULK_PSELECT_LEGACY)
SHADOW(recaulk_pselect_1050, "_pselect$1050", 0)
SHADOW(recaulk_pselect_extsn, "_pselect$DARWIN_EXTSN", RECAULK_PSELECT_EXTSN)
SHADOW(recaulk_pselect_extsn_nocancel, "_pselect$DARWIN_EXTSN$NOCANCEL", RECAULK_PSELECT_EXTSN | RECAULK_PSELECT_NOCANCEL)
SHADOW(recaulk_pselect_nocancel, "_pselect$NOCANCEL", RECAULK_PSELECT_NOCANCEL)
