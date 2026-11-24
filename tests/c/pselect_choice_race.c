/* xnu posts a process-directed signal's EVFILT_SIGNAL knote before it picks the thread that takes the signal
 * (xnu-2422 bsd/kern/kern_sig.c, psignal_internal: proc_knote, then proc_signalstart and get_signalthread).
 * A pselect woken by the knote that blocks the signal again before the pick leaves no thread it is unblocked
 * in, so xnu parks it on the first thread: in a program whose other threads block it, the waiter returns
 * EINTR with its handler never run, and it can sleep in its next wait for good (CI runs 45077977740 and
 * 45193580816; reproduced on a 12-core 10.9 box, 1 in 1500, the signal found pending on the main thread).
 *
 * This program replays that order without the kernel's timing: it interposes Recaulk's select and kevent
 * (librecaulk.a binds them flat, by name) so the waiter's first wait wakes on a knote the kernel has posted
 * but not yet acted on, and the kernel's pick happens when the waiter next sleeps -- when, on a busy or
 * one-CPU machine, the posting thread runs again. pselect must still be one the signal can be delivered to. */
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

typedef int select_fn(int, fd_set *, fd_set *, fd_set *, struct timeval *);
typedef int kevent_fn(int, const struct kevent *, int, struct kevent *, int, const struct timespec *);

static volatile int stage;              /* 0 off; 1 armed; 2 woke on the knote; 3 knote drained; 4 picked */
static volatile sig_atomic_t handled;
static void on_usr1(int sig) { (void)sig; handled = 1; }

static int interposed_select(const char *real, int n, fd_set *r, fd_set *w, fd_set *e, struct timeval *t) {
    static select_fn *fns[2];
    select_fn **f = &fns[strstr(real, "NOCANCEL") != NULL];
    if (!*f) *f = (select_fn *)dlsym(RTLD_NEXT, real);
    if (stage == 1 && n > 0 && r) {
        /* the knote is up: the kqueue, the highest descriptor in the read set, is all that is ready */
        int kq = n - 1;
        FD_ZERO(r);
        if (w) FD_ZERO(w);
        if (e) FD_ZERO(e);
        FD_SET(kq, r);
        stage = 2;
        return 1;
    }
    if (stage == 3) {
        stage = 4;
        kill(getpid(), SIGUSR1); /* the kernel picks a thread now: whichever has SIGUSR1 unblocked */
    }
    return (*f)(n, r, w, e, t);
}
int select_extsn(int, fd_set *, fd_set *, fd_set *, struct timeval *) __asm("_select$DARWIN_EXTSN");
int select_extsn(int n, fd_set *r, fd_set *w, fd_set *e, struct timeval *t) {
    return interposed_select("select$DARWIN_EXTSN", n, r, w, e, t);
}
int select_extsn_nc(int, fd_set *, fd_set *, fd_set *, struct timeval *) __asm("_select$DARWIN_EXTSN$NOCANCEL");
int select_extsn_nc(int n, fd_set *r, fd_set *w, fd_set *e, struct timeval *t) {
    return interposed_select("select$DARWIN_EXTSN$NOCANCEL", n, r, w, e, t);
}
int kevent(int kq, const struct kevent *ch, int nch, struct kevent *ev, int nev, const struct timespec *t) {
    static kevent_fn *f;
    if (!f) f = (kevent_fn *)dlsym(RTLD_NEXT, "kevent");
    if (stage == 2 && nch == 0 && nev > 0) {
        EV_SET(&ev[0], SIGUSR1, EVFILT_SIGNAL, EV_CLEAR, 0, 1, NULL);
        stage = 3;
        return 1;
    }
    return f(kq, ch, nch, ev, nev, t);
}

static void *waiter(void *arg) {
    (void)arg;
    sigset_t open;
    pthread_sigmask(SIG_BLOCK, NULL, &open);
    sigdelset(&open, SIGUSR1);
    struct timespec ts = {5, 0};
    stage = 1;
    int rc = pselect(0, NULL, NULL, NULL, &ts, &open), e = errno;
    int ok = rc == -1 && e == EINTR && handled;
    if (!ok)
        printf("FAIL: pselect_choice_race: rc=%d errno=%d handler=%d stage=%d, want -1 EINTR with the handler run"
               " in the waiting thread\n", rc, rc < 0 ? e : 0, (int)handled, stage);
    return (void *)(intptr_t)!ok;
}

int main(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_usr1;
    sigaction(SIGUSR1, &sa, NULL);
    sigset_t all, old;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, &old); /* this thread, the first, never takes SIGUSR1 while the wait runs */
    pthread_t t;
    void *bad = NULL;
    pthread_create(&t, NULL, waiter, NULL);
    pthread_join(t, &bad);
    if (stage < 4) {
        /* pselect returned before it slept again: the pick comes now, and lands here */
        stage = 4;
        kill(getpid(), SIGUSR1);
    }
    pthread_sigmask(SIG_SETMASK, &old, NULL);
    if (!bad) printf("ok pselect_choice_race\n");
    return bad != NULL;
}
