#ifndef RECAULK_UDP_WAIT_H
#define RECAULK_UDP_WAIT_H
#include <stddef.h>
#include <sys/event.h>

struct recaulk_udp_reader { int fd; void *udata; };
/* Initialize to zero; owned by one event-loop consumer. No descriptors retained. */
struct recaulk_udp_wait_state { size_t next; unsigned prefer_udp; };

__BEGIN_DECLS
/* Source adapter for Mavericks' missing empty-datagram kqueue notifications.
 * Submit changes to kqueue normally, then pass a snapshot of its enabled,
 * level-triggered UDP read registrations. Keep those descriptors alive and the
 * snapshot unchanged throughout this call. Other kqueue filters remain native.
 * Synthesized UDP events have data=0, a readiness hint rather than a byte count;
 * callers must receive the datagram to determine its size.
 * Capacity must be positive. Timeout/EINTR follow kevent wait semantics.
 * State provides fair delivery when the output buffer is smaller than the ready
 * set; it contains no registration ownership and survives descriptor reuse. */
int __recaulk_kevent_wait_udp(int kq, struct kevent *events, int capacity,
    const struct timespec *timeout, const struct recaulk_udp_reader *readers,
    size_t count, struct recaulk_udp_wait_state *state);
__END_DECLS
#endif
