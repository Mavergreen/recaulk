/*
 * preadv and pwritev (macOS 11) for 10.9 -- custom backfill (not from macports-legacy-support).
 * The generated forwarding layer prefers the native API on newer macOS.
 *
 * Positional, like pread and pwrite: the file offset never moves. Arguments are refused as the
 * kernel's preadv refuses them, before any I/O: an iovcnt outside 1..IOV_MAX, or iov_len values
 * whose sum exceeds SSIZE_MAX, is EINVAL. Short transfers are POSIX's: the count of bytes moved.
 *
 * Atomicity: one iovec, or several moving at most RECAULK_IOV_BOUNCE bytes in all, take a single
 * pread or pwrite (through a bounce buffer for several), as atomic as the system call itself.
 * Larger transfers, or several iovecs when the bounce buffer cannot be allocated, take one pread or
 * pwrite per iovec, so a concurrent writer to the same range may interleave with them. Each call
 * still stops at the first short or failed one, and reports what had moved before it.
 */
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

#define RECAULK_IOV_BOUNCE (1024 * 1024)

ssize_t preadv(int fd, const struct iovec *iov, int iovcnt, off_t offset);
ssize_t pwritev(int fd, const struct iovec *iov, int iovcnt, off_t offset);

static ssize_t iov_total(const struct iovec *iov, int iovcnt) {
    size_t total = 0;
    int i;
    if (iovcnt <= 0 || iovcnt > IOV_MAX) {
        errno = EINVAL;
        return -1;
    }
    for (i = 0; i < iovcnt; i++) {
        if (iov[i].iov_len > (size_t)SSIZE_MAX - total) {
            errno = EINVAL;
            return -1;
        }
        total += iov[i].iov_len;
    }
    return (ssize_t)total;
}

static ssize_t each_iovec(int fd, const struct iovec *iov, int iovcnt, off_t offset, int writing) {
    ssize_t done = 0, n;
    int i;
    for (i = 0; i < iovcnt; i++) {
        n = writing ? pwrite(fd, iov[i].iov_base, iov[i].iov_len, offset + done)
                    : pread(fd, iov[i].iov_base, iov[i].iov_len, offset + done);
        if (n < 0) return done ? done : -1;
        done += n;
        if ((size_t)n < iov[i].iov_len) break;
    }
    return done;
}

ssize_t preadv(int fd, const struct iovec *iov, int iovcnt, off_t offset) {
    ssize_t total = iov_total(iov, iovcnt), n;
    unsigned char *buf;
    int i, saved;
    size_t at, take;
    if (total < 0) return -1;
    if (iovcnt == 1) return pread(fd, iov[0].iov_base, iov[0].iov_len, offset);
    if (total <= RECAULK_IOV_BOUNCE && (buf = malloc(total ? (size_t)total : 1)) != NULL) {
        n = pread(fd, buf, (size_t)total, offset);
        saved = errno;
        for (i = 0, at = 0; n > 0 && at < (size_t)n; i++) {
            take = iov[i].iov_len < (size_t)n - at ? iov[i].iov_len : (size_t)n - at;
            if (take) memcpy(iov[i].iov_base, buf + at, take);
            at += take;
        }
        free(buf);
        errno = saved;
        return n;
    }
    return each_iovec(fd, iov, iovcnt, offset, 0);
}

ssize_t pwritev(int fd, const struct iovec *iov, int iovcnt, off_t offset) {
    ssize_t total = iov_total(iov, iovcnt), n;
    unsigned char *buf;
    int i, saved;
    size_t at;
    if (total < 0) return -1;
    if (iovcnt == 1) return pwrite(fd, iov[0].iov_base, iov[0].iov_len, offset);
    if (total <= RECAULK_IOV_BOUNCE && (buf = malloc(total ? (size_t)total : 1)) != NULL) {
        for (i = 0, at = 0; i < iovcnt; i++) {
            if (iov[i].iov_len) memcpy(buf + at, iov[i].iov_base, iov[i].iov_len);
            at += iov[i].iov_len;
        }
        n = pwrite(fd, buf, (size_t)total, offset);
        saved = errno;
        free(buf);
        errno = saved;
        return n;
    }
    return each_iovec(fd, iov, iovcnt, offset, 1);
}
