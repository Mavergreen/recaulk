/* platform: Mavericks kqueue tests UDP payload bytes, but select tests packet
 * presence. Supplement UDP read events; never consume packets or socket errors.
 * The caller supplies its live registrations, avoiding a second fd registry. */
#define _DARWIN_UNLIMITED_SELECT 1
#include <recaulk/udp_wait.h>
#include <errno.h>
#include <limits.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>

/* FIONREAD includes address metadata on Mavericks (even an empty IPv4 packet
 * reports 16 bytes), so it cannot identify empty payloads. Readiness is enough;
 * synthetic events intentionally make no payload-size promise. */
static int udp_ready(const struct recaulk_udp_reader *r, fd_set *ready) {
    return FD_ISSET(r->fd, ready) != 0;
}

int __recaulk_kevent_wait_udp(int kq, struct kevent *events, int capacity,
    const struct timespec *timeout, const struct recaulk_udp_reader *readers,
    size_t count, struct recaulk_udp_wait_state *state) {
    if (capacity <= 0 || !events || (count && (!readers || !state)) ||
        (timeout && (timeout->tv_sec < 0 || timeout->tv_nsec < 0 ||
                     timeout->tv_nsec >= 1000000000))) {
        errno = EINVAL;
        return -1;
    }
    if (!count) return kevent(kq, NULL, 0, events, capacity, timeout);
    if (kq < 0 || kq == INT_MAX) { errno = EBADF; return -1; }
    int maxfd = kq;
    for (size_t i = 0; i < count; i++) {
        if (readers[i].fd < 0 || readers[i].fd == INT_MAX) {
            errno = EBADF; return -1;
        }
        if (readers[i].fd > maxfd) maxfd = readers[i].fd;
    }
    /* FD_SET permits arbitrary descriptor numbers with UNLIMITED_SELECT, but
     * the backing storage must also grow beyond the fixed fd_set typedef. */
    size_t bytes = (((size_t)maxfd + 1 + 31) / 32) * sizeof(uint32_t);
    if (bytes < sizeof(fd_set)) bytes = sizeof(fd_set);
    fd_set *ready = calloc(1, bytes);
    if (!ready) return -1;
    mach_timebase_info_data_t scale;
    mach_timebase_info(&scale);
    uint64_t start = mach_absolute_time();
    long double budget = timeout ? (long double)timeout->tv_sec * 1000000000 +
                                  timeout->tv_nsec : 0;
    int first = 1, result = -1;
    struct timespec zero = {0, 0};
    for (;;) {
        memset(ready, 0, bytes);
        FD_SET(kq, ready);
        for (size_t i = 0; i < count; i++) FD_SET(readers[i].fd, ready);
        struct timeval wait = {0, 0};
        struct timeval *waitp = &wait;
        if (!first) {
            if (!timeout) waitp = NULL;
            else {
                long double elapsed = (long double)(mach_absolute_time() - start) *
                                      scale.numer / scale.denom;
                long double left = budget - elapsed;
                if (left <= 0) { result = 0; break; }
                wait.tv_sec = (time_t)(left / 1000000000);
                long double fraction = left - (long double)wait.tv_sec * 1000000000;
                wait.tv_usec = (suseconds_t)((fraction + 999) / 1000);
                if (wait.tv_usec >= 1000000) { wait.tv_sec++; wait.tv_usec = 0; }
            }
        }
        int selected = select(maxfd + 1, ready, NULL, NULL, waitp);
        if (selected < 0) break; /* Includes EINTR; caller decides whether to retry. */
        size_t begin = state->next % count;
        int have_udp = 0;
        for (size_t j = 0; j < count; j++) {
            int found = udp_ready(readers + ((begin + j) % count), ready);
            if (found) { have_udp = 1; break; }
        }
        /* Reserve delivery for both classes; with a single slot, alternate.
         * Native events are never fetched unless there is room to return them. */
        int reserve = have_udp && (capacity > 1 || state->prefer_udp);
        int n = capacity > reserve ?
            kevent(kq, NULL, 0, events, capacity - reserve, &zero) : 0;
        if (n < 0) break;
        size_t next = begin;
        /* Modern kernels can deliver these UDP readers natively. Advance the
         * same cursor for those events so alternating classes remains fair. */
        for (int k = 0; k < n; k++) {
            if (events[k].filter != EVFILT_READ) continue;
            for (size_t i = 0; i < count; i++)
                if (events[k].ident == (uintptr_t)readers[i].fd)
                    next = (i + 1) % count;
        }
        for (size_t j = 0; j < count && n < capacity; j++) {
            size_t i = (begin + j) % count;
            int found = udp_ready(readers + i, ready);
            if (!found) continue;
            int duplicate = 0;
            for (int k = 0; k < n; k++)
                duplicate |= events[k].filter == EVFILT_READ &&
                             events[k].ident == (uintptr_t)readers[i].fd;
            if (duplicate) continue;
            EV_SET(events + n, readers[i].fd, EVFILT_READ, 0, 0, 0, readers[i].udata);
            n++;
            next = (i + 1) % count;
        }
        if (n) {
            state->next = next;
            state->prefer_udp = !state->prefer_udp;
            result = n;
            break;
        }
        if (timeout && budget == 0) { result = 0; break; }
        first = 0;
    }
    int saved = errno;
    free(ready);
    errno = saved;
    return result;
}
