/* spec: README.md "The kernel-fixes kext" -- a smoke test of kevent with kqueue_scan_restart applied: one thread
   waits in kevent on a kqueue watching a pipe; another closes the kqueue. The wait must come back (10.9 wakes it
   THREAD_INTERRUPTED, xnu-2422.115.4 bsd/kern/kern_event.c kqueue_wakeup), and the machine must stay up.
   It does not reach the patched panic, which needs a stale THREAD_RESTART on the waiting thread. */
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/event.h>
#include <unistd.h>

static int kq;

static void *
waiter(void *arg)
{
	struct kevent ev;
	int *res = arg;
	res[0] = kevent(kq, NULL, 0, &ev, 1, NULL);
	res[1] = errno;
	return NULL;
}

int
main(void)
{
	int p[2], res[2] = { 0, 0 };
	pthread_t t;
	struct kevent ev;
	if (pipe(p) != 0 || (kq = kqueue()) < 0)
		return perror("setup"), 1;
	EV_SET(&ev, p[0], EVFILT_READ, EV_ADD, 0, 0, NULL);
	if (kevent(kq, &ev, 1, NULL, 0, NULL) != 0)
		return perror("kevent add"), 1;
	if (pthread_create(&t, NULL, waiter, res) != 0)
		return 1;
	usleep(200000);
	close(kq);
	pthread_join(t, NULL);
	printf("kevent=%d errno=%d\n", res[0], res[0] < 0 ? res[1] : 0);
	return 0;
}
