/* Catch missing exports, a moved file offset, lost data, wrong short transfers, and wrong errors. */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/uio.h>
#include <unistd.h>

/* The 10.9 SDK declares neither; macOS 11 declares them in <sys/uio.h>. */
extern ssize_t preadv(int, const struct iovec *, int, off_t);
extern ssize_t pwritev(int, const struct iovec *, int, off_t);

static int failures;
#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL line %d: %s (errno %d)\n", __LINE__, #cond, errno); failures++; } } while (0)

static void check_pair(int fd, size_t chunk, int iovcnt) {
    size_t total = chunk * (size_t)iovcnt, i;
    unsigned char *src = malloc(total), *dst = malloc(total);
    struct iovec *in = calloc((size_t)iovcnt, sizeof *in), *out = calloc((size_t)iovcnt, sizeof *out);
    off_t at = 4096;
    CHECK(src && dst && in && out);
    for (i = 0; i < total; i++) src[i] = (unsigned char)(i * 7 + iovcnt);
    memset(dst, 0, total);
    for (i = 0; i < (size_t)iovcnt; i++) {
        in[i].iov_base = src + i * chunk; in[i].iov_len = chunk;
        out[i].iov_base = dst + i * chunk; out[i].iov_len = chunk;
    }
    CHECK(lseek(fd, 17, SEEK_SET) == 17);
    CHECK(pwritev(fd, in, iovcnt, at) == (ssize_t)total);
    CHECK(lseek(fd, 0, SEEK_CUR) == 17);
    CHECK(preadv(fd, out, iovcnt, at) == (ssize_t)total);
    CHECK(lseek(fd, 0, SEEK_CUR) == 17);
    CHECK(memcmp(src, dst, total) == 0);
    free(src); free(dst); free(in); free(out);
}

int main(void) {
    char path[] = "/tmp/recaulk-preadv.XXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    unlink(path);

    /* Small, several iovecs, one of them empty: one transfer, file offset untouched. */
    {
        char a[] = "hello, ", b[] = "", c[] = "positional world";
        struct iovec w[3] = {{a, 7}, {b, 0}, {c, 16}};
        char x[5], y[3], z[15];
        struct iovec r[3] = {{x, sizeof x}, {y, sizeof y}, {z, sizeof z}};
        CHECK(lseek(fd, 3, SEEK_SET) == 3);
        CHECK(pwritev(fd, w, 3, 100) == 23);
        CHECK(lseek(fd, 0, SEEK_CUR) == 3);
        CHECK(preadv(fd, r, 3, 100) == 23);
        CHECK(lseek(fd, 0, SEEK_CUR) == 3);
        CHECK(memcmp(x, "hello", 5) == 0 && memcmp(y, ", p", 3) == 0 && memcmp(z, "ositional world", 15) == 0);

        /* Short transfer at end of file: the bytes there, then 0 at EOF. */
        char p[4], q[64];
        struct iovec s[2] = {{p, sizeof p}, {q, sizeof q}};
        memset(q, 'Q', sizeof q);
        CHECK(preadv(fd, s, 2, 113) == 10);
        CHECK(memcmp(p, "onal", 4) == 0 && memcmp(q, " world", 6) == 0 && q[6] == 'Q');
        CHECK(preadv(fd, s, 2, 123) == 0);
        CHECK(preadv(fd, s, 2, 9999) == 0);
    }

    /* One iovec, many iovecs, and a transfer large enough to exceed any bounce buffer. */
    check_pair(fd, 1, 1);
    check_pair(fd, 512, 3);
    check_pair(fd, 1, 1024);
    check_pair(fd, 1 << 20, 3);

    /* POSIX errors. */
    {
        char a[8];
        struct iovec v[2] = {{a, 4}, {a + 4, 4}};
        struct iovec big[2] = {{a, (size_t)SSIZE_MAX}, {a, 1}};
        static struct iovec many[IOV_MAX + 1];
        int p[2];
        size_t i;
        for (i = 0; i < sizeof many / sizeof many[0]; i++) { many[i].iov_base = a; many[i].iov_len = 1; }

        errno = 0; CHECK(preadv(fd, v, 0, 0) == -1 && errno == EINVAL);
        errno = 0; CHECK(pwritev(fd, v, 0, 0) == -1 && errno == EINVAL);
        errno = 0; CHECK(preadv(fd, v, -1, 0) == -1 && errno == EINVAL);
        errno = 0; CHECK(preadv(fd, many, IOV_MAX + 1, 0) == -1 && errno == EINVAL);
        errno = 0; CHECK(pwritev(fd, many, IOV_MAX + 1, 0) == -1 && errno == EINVAL);
        errno = 0; CHECK(preadv(fd, big, 2, 0) == -1 && errno == EINVAL);
        errno = 0; CHECK(pwritev(fd, big, 2, 0) == -1 && errno == EINVAL);
        errno = 0; CHECK(preadv(fd, v, 2, -1) == -1 && errno == EINVAL);
        errno = 0; CHECK(pwritev(fd, v, 2, -1) == -1 && errno == EINVAL);
        errno = 0; CHECK(preadv(-1, v, 2, 0) == -1 && errno == EBADF);
        errno = 0; CHECK(pwritev(-1, v, 2, 0) == -1 && errno == EBADF);
        CHECK(pipe(p) == 0);
        errno = 0; CHECK(preadv(p[0], v, 2, 0) == -1 && errno == ESPIPE);
        errno = 0; CHECK(pwritev(p[1], v, 2, 0) == -1 && errno == ESPIPE);
        close(p[0]); close(p[1]);
    }

    /* A read-only descriptor refuses pwritev; a write-only one refuses preadv. */
    {
        char a[4] = "abcd";
        struct iovec v[2] = {{a, 2}, {a + 2, 2}};
        int ro = open("/dev/null", O_RDONLY), wo = open("/dev/null", O_WRONLY);
        CHECK(ro >= 0 && wo >= 0);
        errno = 0; CHECK(pwritev(ro, v, 2, 0) == -1 && errno == EBADF);
        errno = 0; CHECK(preadv(wo, v, 2, 0) == -1 && errno == EBADF);
        close(ro); close(wo);
    }

    close(fd);
    if (failures) return 1;
    puts("preadv/pwritev: data, untouched offset, short transfers and errors passed");
    return 0;
}
