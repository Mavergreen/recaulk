/* spec: README.md "The kernel-fixes kext" -- wait_result_prepost's reproducer (tests/kfix-wait-result-kit.sh).
   One thread (the waiter) leaves a known wait_result behind, then calls kevent with no timeout on a kqueue
   watching a Mach port set; another (the sender) sends a message to a port in that set a little later, so that
   it may land between kevent's scan and its wait. Unfixed, that wait takes the preposted fast path and
   kqueue_scan_continue sees the leftover wait_result:
     silent:  the leftover is THREAD_TIMED_OUT (a 1 ms kevent on the empty kqueue): kevent returns 0 events,
              which a kevent with no timeout never may;
     restart: the leftover is THREAD_RESTART (a Mach receive on a port the third thread, the destroyer, destroys,
              MACH_RCV_PORT_DIED): the panic "invalid wait_result (3)", or with kqueue_scan_restart, -1 EBADF.
   Fixed, kevent returns the one event every time.

   usage: kfix_wait_result silent|restart ITERATIONS DELAY_US SECONDS
   DELAY_US is how long after the waiter is about to call kevent the sender sends; a negative -N picks it at random
   each time, below N/100, N/10 or N us (the no-DTrace stress). It stops after ITERATIONS or SECONDS, whichever
   comes first, and
   prints one RESULT line. Its exit status is 0 unless it could not run. */
#include <errno.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <time.h>
#include <unistd.h>

static mach_port_t pset, port;
static int kq;
static volatile int go, sent, quit;
static volatile long delay_us;
static mach_timebase_info_data_t tb;

static uint64_t
now_us(void)
{
	return mach_absolute_time() * tb.numer / tb.denom / 1000;
}

static void
spin_us(long us)
{
	uint64_t until = now_us() + (uint64_t)us;
	while (now_us() < until)
		;
}

static void
die(const char *what, kern_return_t kr)
{
	printf("ERROR %s: %d (%s)\n", what, kr, mach_error_string(kr));
	exit(2);
}

/* the sender: spins for go (a sleep would add its wake-up latency to the delay), then sends one message */
static void *
sender(void *arg)
{
	(void)arg;
	for (;;) {
		while (!go && !quit)
			;
		if (quit)
			return NULL;
		go = 0;
		/* -N: at random below N/100, N/10 or N, so one setting fits a fast Mac and an emulated guest */
		long n = -delay_us / (long[]){ 100, 10, 1 }[random() % 3];
		spin_us(delay_us >= 0 ? delay_us : n > 0 ? random() % n : 0);
		mach_msg_header_t m;
		memset(&m, 0, sizeof m);
		m.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
		m.msgh_size = sizeof m;
		m.msgh_remote_port = port;
		m.msgh_id = 0x6b77;
		kern_return_t kr = mach_msg(&m, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof m, 0, MACH_PORT_NULL, 1000,
		    MACH_PORT_NULL);
		if (kr != KERN_SUCCESS)
			die("send", kr);
		__sync_synchronize();
		sent = 1;
	}
}

/* take every message off the port without waiting */
static void
drain(void)
{
	for (;;) {
		struct {
			mach_msg_header_t h;
			mach_msg_trailer_t t;
		} m;
		kern_return_t kr = mach_msg(&m.h, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof m, port, 0, MACH_PORT_NULL);
		if (kr == MACH_RCV_TIMED_OUT)
			return;
		if (kr != KERN_SUCCESS)
			die("drain", kr);
	}
}

static mach_port_t doomed;
static volatile int receiving, destroyed;

/* the destroyer: once the waiter is about to block in its receive, gives it 2 ms to get there, then destroys the
   port, which wakes it THREAD_RESTART (xnu-2422.115.4 osfmk/ipc/ipc_mqueue.c, ipc_mqueue_changed) */
static void *
destroyer(void *arg)
{
	(void)arg;
	for (;;) {
		while (!receiving && !quit)
			usleep(50);
		if (quit)
			return NULL;
		receiving = 0;
		usleep(2000);
		kern_return_t kr = mach_port_mod_refs(mach_task_self(), doomed, MACH_PORT_RIGHT_RECEIVE, -1);
		if (kr != KERN_SUCCESS)
			die("destroy", kr);
		__sync_synchronize();
		destroyed = 1;
	}
}

int
main(int argc, char **argv)
{
	if (argc != 5 || (strcmp(argv[1], "silent") != 0 && strcmp(argv[1], "restart") != 0)) {
		fprintf(stderr, "usage: kfix_wait_result silent|restart ITERATIONS DELAY_US SECONDS\n");
		return 2;
	}
	int restart = strcmp(argv[1], "restart") == 0;
	long iters = atol(argv[2]), seconds = atol(argv[4]);
	delay_us = atol(argv[3]);
	mach_timebase_info(&tb);
	srandom((unsigned)getpid());
	kern_return_t kr;
	mach_port_t self = mach_task_self();
	if ((kr = mach_port_allocate(self, MACH_PORT_RIGHT_PORT_SET, &pset)) != KERN_SUCCESS)
		die("port set", kr);
	if ((kr = mach_port_allocate(self, MACH_PORT_RIGHT_RECEIVE, &port)) != KERN_SUCCESS)
		die("port", kr);
	if ((kr = mach_port_insert_right(self, port, port, MACH_MSG_TYPE_MAKE_SEND)) != KERN_SUCCESS)
		die("send right", kr);
	if ((kr = mach_port_move_member(self, port, pset)) != KERN_SUCCESS)
		die("move member", kr);
	if ((kq = kqueue()) < 0)
		return perror("kqueue"), 2;
	struct kevent ev;
	EV_SET(&ev, pset, EVFILT_MACHPORT, EV_ADD, 0, 0, NULL);
	if (kevent(kq, &ev, 1, NULL, 0, NULL) != 0)
		return perror("kevent add"), 2;
	pthread_t ts, td;
	if (pthread_create(&ts, NULL, sender, NULL) != 0 || pthread_create(&td, NULL, destroyer, NULL) != 0)
		return 2;

	long n = 0, one = 0, zero = 0, eintr = 0, ebadf = 0, other = 0, unprimed = 0;
	uint64_t end = now_us() + (uint64_t)seconds * 1000000;
	struct timespec ms1 = { 0, 1000000 };
	while (n < iters && now_us() < end) {
		drain();
		/* leave the wait_result behind */
		if (restart) {
			if ((kr = mach_port_allocate(self, MACH_PORT_RIGHT_RECEIVE, &doomed)) != KERN_SUCCESS)
				die("doomed port", kr);
			mach_msg_header_t h;
			destroyed = 0;
			__sync_synchronize();
			receiving = 1;
			kr = mach_msg(&h, MACH_RCV_MSG, 0, sizeof h, doomed, 0, MACH_PORT_NULL);
			while (!destroyed)
				;
			if (kr != MACH_RCV_PORT_DIED) {
				unprimed++;	/* destroyed before it blocked: no THREAD_RESTART left behind */
				continue;
			}
		} else {
			int r = kevent(kq, NULL, 0, &ev, 1, &ms1);
			if (r != 0) {
				unprimed++;	/* a message was already there, or a signal: no THREAD_TIMED_OUT */
				continue;
			}
		}
		/* nothing may wait between here and the kevent, or it overwrites what was left */
		sent = 0;
		__sync_synchronize();
		go = 1;
		int r = kevent(kq, NULL, 0, &ev, 1, NULL);
		int e = errno;
		n++;
		if (r == 1)
			one++;
		else if (r == 0)
			zero++;
		else if (e == EINTR)
			eintr++;
		else if (e == EBADF)
			ebadf++;
		else
			other++;
		while (!sent)
			usleep(100);
	}
	quit = 1;
	printf("RESULT mode=%s iterations=%ld events=%ld zero=%ld eintr=%ld ebadf=%ld other=%ld unprimed=%ld delay_us=%ld\n",
	    argv[1], n, one, zero, eintr, ebadf, other, unprimed, (long)delay_us);
	return 0;
}
