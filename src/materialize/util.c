/* recaulk-materialize's shared helpers: the one-line refusal, allocation, whole-file reads. */
#include "materialize.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

void mz_fail(const char *fmt, ...) {
    va_list ap;
    fputs("recaulk-materialize: ", stderr);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

void *mz_xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (!p) mz_fail("out of memory");
    return p;
}

char *mz_xstrdup(const char *s) {
    size_t n = strlen(s) + 1;
    return memcpy(mz_xmalloc(n), s, n);
}

int mz_read_file(const char *path, char **buf, size_t *n) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    size_t cap = 65536, len = 0;
    char *b = mz_xmalloc(cap + 1);
    for (;;) {
        size_t got = fread(b + len, 1, cap - len, f);
        len += got;
        if (len < cap) break;
        cap *= 2;
        char *nb = realloc(b, cap + 1);
        if (!nb) mz_fail("out of memory");
        b = nb;
    }
    int bad = ferror(f);
    fclose(f);
    if (bad) { free(b); return -1; }
    b[len] = 0;
    *buf = b;
    *n = len;
    return 0;
}
