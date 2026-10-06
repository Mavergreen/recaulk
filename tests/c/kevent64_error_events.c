/*
 * Behavioural test for the kevent64 shim's KEVENT_FLAG_ERROR_EVENTS emulation,
 * run by `make test`.
 *
 * uSockets registers filters with FLAG_ERROR_EVENTS (0x2), which on 10.10+
 * means "apply these changes, hand back only the ones that failed". 10.9 does
 * not know the flag. Each check below is a property of the real modern-kernel
 * behaviour that Bun relies on.
 *
 * The one that matters most is the first: a registration whose fd is closed
 * before the next wait must never be reported, even if a new fd has since been
 * given the same number. uSockets frees the us_poll_t along with the fd, so a
 * report carries a dangling udata into us_internal_dispatch_ready_poll.
 */

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <sys/socket.h>
#include <unistd.h>

#define KEVENT_FLAG_ERROR_EVENTS 0x2

static int failures = 0;

#define CHECK(cond) do {                                              \
    if (cond) { printf("  ok   : %s\n", #cond); }                     \
    else { printf("  FAIL : %s  (errno=%d %s)\n", #cond, errno,       \
                  strerror(errno)); ++failures; }                     \
  } while (0)

static const struct timespec zero = {0, 0};

/* A connected socket is writable at once: the "ready at registration" case. */
static int
writable_fd(void)
{
  int sv[2];
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return -1;
  return sv[0];
}

static int
wait_for(int kq, uint64_t udata)
{
  struct kevent64_s out[16];
  int n = kevent64(kq, NULL, 0, out, 16, 0, &zero);
  for (int i = 0; i < n; i++)
    if (out[i].udata == udata) return 1;
  return 0;
}

static void
on_alarm(int sig)
{
  (void)sig;
  static const char msg[] = "  FAIL : kevent64 with FLAG_ERROR_EVENTS blocked\n";
  write(2, msg, sizeof msg - 1);
  _exit(1);
}

int
main(void)
{
  struct kevent64_s ch[2], out[2];
  int rc;

  /* ---- a closed-then-reused fd is never reported with the old udata ---- */
  {
    int kq = kqueue();
    int fd = writable_fd();
    EV_SET64(&ch[0], fd, EVFILT_WRITE, EV_ADD | EV_ONESHOT, 0, 0, 0xdead, 0, 0);
    rc = kevent64(kq, ch, 1, out, 1, KEVENT_FLAG_ERROR_EVENTS, &zero);
    CHECK(rc == 0);
    close(fd);
    int reused = writable_fd();
    CHECK(reused == fd);                  /* the precondition for the bug */
    CHECK(!wait_for(kq, 0xdead));
    close(reused);
    close(kq);
  }

  /* ---- a ready event is not lost: it arrives on the next wait ---- */
  {
    int kq = kqueue();
    int fd = writable_fd();
    EV_SET64(&ch[0], fd, EVFILT_WRITE, EV_ADD | EV_ONESHOT, 0, 0, 0xbeef, 0, 0);
    rc = kevent64(kq, ch, 1, out, 1, KEVENT_FLAG_ERROR_EVENTS, &zero);
    CHECK(rc == 0);
    CHECK(wait_for(kq, 0xbeef));
    close(fd);
    close(kq);
  }

  /* ---- EV_DISPATCH (Bun's stdin) still fires after registration ---- */
  {
    int kq = kqueue();
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    write(sv[1], "x", 1);                 /* readable before we register */
    EV_SET64(&ch[0], sv[0], EVFILT_READ, EV_ADD | EV_DISPATCH, 0, 0, 0xd15, 0, 0);
    rc = kevent64(kq, ch, 1, out, 1, KEVENT_FLAG_ERROR_EVENTS, &zero);
    CHECK(rc == 0);
    CHECK(wait_for(kq, 0xd15));
    close(sv[0]); close(sv[1]);
    close(kq);
  }

  /* ---- errors are reported per change, and the rest of the batch applies ---- */
  {
    int kq = kqueue();
    int fd = writable_fd();
    EV_SET64(&ch[0], fd, EVFILT_READ, EV_DELETE, 0, 0, 0xe1, 0, 0);   /* never added */
    EV_SET64(&ch[1], fd, EVFILT_WRITE, EV_ADD | EV_ONESHOT, 0, 0, 0xe2, 0, 0);
    rc = kevent64(kq, ch, 2, out, 2, KEVENT_FLAG_ERROR_EVENTS, &zero);
    CHECK(rc == 1);
    CHECK(rc == 1 && (out[0].flags & EV_ERROR) && out[0].data == ENOENT);
    CHECK(rc == 1 && out[0].udata == 0xe1);
    CHECK(wait_for(kq, 0xe2));
    close(fd);
    close(kq);
  }

  /* ---- more changes than eventlist slots: nothing written past the end ---- */
  {
    int kq = kqueue();
    int a = writable_fd(), b = writable_fd();
    struct kevent64_s guarded[2];
    memset(guarded, 0xa5, sizeof guarded);
    EV_SET64(&ch[0], a, EVFILT_WRITE, EV_ADD | EV_ONESHOT, 0, 0, 0xa, 0, 0);
    EV_SET64(&ch[1], b, EVFILT_WRITE, EV_ADD | EV_ONESHOT, 0, 0, 0xb, 0, 0);
    rc = kevent64(kq, ch, 2, guarded, 1, KEVENT_FLAG_ERROR_EVENTS, &zero);
    CHECK(rc == 0);
    CHECK(guarded[1].udata == 0xa5a5a5a5a5a5a5a5ULL);
    close(a); close(b);
    close(kq);
  }

  /* ---- NULL timeout with nothing ready still returns at once ---- */
  {
    int kq = kqueue();
    int sv[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
    EV_SET64(&ch[0], sv[0], EVFILT_READ, EV_ADD, 0, 0, 0x7, 0, 0);
    signal(SIGALRM, on_alarm);
    alarm(5);
    rc = kevent64(kq, ch, 1, out, 1, KEVENT_FLAG_ERROR_EVENTS, NULL);
    alarm(0);
    CHECK(rc == 0);
    close(sv[0]); close(sv[1]);
    close(kq);
  }

  if (failures) printf("kevent64_error_events: %d FAILED\n", failures);
  else          printf("kevent64_error_events: all passed\n");
  return failures ? 1 : 0;
}
