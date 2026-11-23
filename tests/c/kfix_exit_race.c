/* platform: 10.9.5 13F1911 panic 2026-11-23 (proc_exit -> psignal -> thread_abort_safely on a freed thread).
   Minimal shape: the parent's only thread with SIGCHLD unblocked SLEEPS in the kernel (read on a pipe), so the
   child's SIGCHLD picks it without it ever processing signals; the parent's main thread (SIGCHLD blocked) calls
   _exit, so exit1 terminates the sleeper, which is freed, while main is the last thread out and waits in
   proc_exit's proc_sigdrain. usage: kfix_exit_race PARENTS [GAP_USEC] [CHILD_SPIN] [MAIN_SPIN] */
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
static int fds[2];
static void on_chld(int s) { (void)s; }
static void spin(unsigned n) { for (volatile unsigned i = 0; i < n; i++) {} }
static void *sleeper(void *a) {
	(void)a;
	sigset_t s; sigemptyset(&s); sigaddset(&s, SIGCHLD); pthread_sigmask(SIG_UNBLOCK, &s, NULL);
	char c;
	for (;;) (void)read(fds[0], &c, 1);	/* never written: an interruptible kernel sleep */
	return NULL;
}
int main(int argc, char **argv) {
	int n = argc > 1 ? atoi(argv[1]) : 1000, gap = argc > 2 ? atoi(argv[2]) : 0;
	unsigned cspin = argc > 3 ? (unsigned)atoi(argv[3]) : 100000, mspin = argc > 4 ? (unsigned)atoi(argv[4]) : 1000000;
	for (int i = 0; i < n; i++) {
		pid_t p = fork();
		if (p < 0) { perror("fork"); return 1; }
		if (p == 0) {
			struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_handler = on_chld; sigaction(SIGCHLD, &sa, NULL);
			sigset_t s; sigemptyset(&s); sigaddset(&s, SIGCHLD); pthread_sigmask(SIG_BLOCK, &s, NULL);
			if (pipe(fds) != 0) _exit(2);	/* without it the sleeper would not sleep: no race */
			pthread_t t; pthread_create(&t, NULL, sleeper, NULL);
			usleep(1000);	/* the sleeper is asleep in read */
			pid_t c = fork();
			if (c < 0) _exit(2);
			if (c == 0) { spin(cspin); _exit(0); }
			spin(mspin);	/* the child exits meanwhile: its SIGCHLD picks the sleeper */
			_exit(0);
		}
		int st;
		if (waitpid(p, &st, 0) != p || !WIFEXITED(st) || WEXITSTATUS(st) != 0) {
			fprintf(stderr, "parent %d did not set up the race\n", i);
			return 1;
		}
		if (gap > 0) usleep((useconds_t)gap);
	}
	printf("survived %d\n", n);
	return 0;
}
