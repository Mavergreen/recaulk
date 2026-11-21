/* spec: tests/kext-runtime-test.sh -- decision E's reconciliation, in one process so nothing races: TRIALS times,
   watch FILE with EVFILT_VNODE (NOTE_WRITE|NOTE_EXTEND|NOTE_ATTRIB), read debug.recaulk_kpi.vnode_notify_forwarded,
   have the probe call vnode_notify(FILE, 0xe), wait up to 2 s for the event, and read the counter again.
   Prints "delivered D/T forwarded F/T" plus one line per trial that went otherwise; exits 0. Runs as root. */
#include <sys/types.h>
#include <sys/event.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static uint64_t
forwarded(void)
{
	uint64_t v = 0;
	size_t n = sizeof v;

	if (sysctlbyname("debug.recaulk_kpi.vnode_notify_forwarded", &v, &n, NULL, 0) != 0) {
		perror("debug.recaulk_kpi.vnode_notify_forwarded");
		exit(2);
	}
	return v;
}

int
main(int argc, char **argv)
{
	int trials, i, delivered = 0, fwd = 0;

	if (argc != 3) {
		fprintf(stderr, "usage: kext_notify_watch FILE TRIALS\n");
		return 2;
	}
	trials = atoi(argv[2]);
	for (i = 0; i < trials; i++) {
		int fd = open(argv[1], O_RDONLY | O_EVTONLY), kq = kqueue(), err = 0;
		size_t en = sizeof err;
		struct kevent ev;
		struct timespec ts = { 2, 0 };
		uint64_t before, after;
		int got;

		if (fd < 0 || kq < 0) {
			perror(argv[1]);
			return 2;
		}
		EV_SET(&ev, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_WRITE | NOTE_EXTEND | NOTE_ATTRIB, 0, NULL);
		if (kevent(kq, &ev, 1, NULL, 0, NULL) != 0) {
			perror("kevent EV_ADD");
			return 2;
		}
		before = forwarded();
		if (sysctlbyname("debug.recaulk_kpi_probe.notify", NULL, NULL, argv[1], strlen(argv[1]) + 1) != 0) {
			perror("debug.recaulk_kpi_probe.notify");
			return 2;
		}
		if (sysctlbyname("debug.recaulk_kpi_probe.error", &err, &en, NULL, 0) != 0 || err != 0) {
			printf("trial %d: the probe's vnode_notify path failed, errno %d\n", i, err);
		}
		got = kevent(kq, NULL, 0, &ev, 1, &ts);
		after = forwarded();
		if (got == 1 && ev.fflags == 0xe) {
			delivered++;
		} else {
			printf("trial %d: %s (fflags 0x%x)\n", i, got == 1 ? "other flags" : "no event in 2 s", got == 1 ? ev.fflags : 0);
		}
		if (after - before == 1) {
			fwd++;
		} else {
			printf("trial %d: the counter rose by %llu\n", i, (unsigned long long)(after - before));
		}
		close(kq);
		close(fd);
	}
	printf("delivered %d/%d forwarded %d/%d\n", delivered, trials, fwd, trials);
	return 0;
}
