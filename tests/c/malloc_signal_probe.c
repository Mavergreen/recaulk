/* A preloaded probe for tests/materialize-signal.sh. Once the program has called mkdtemp (its stage exists), the
 * RECAULK_PROBE_AFTER-th allocation raises RECAULK_PROBE_SIGNAL from inside malloc, as a signal landing mid-malloc
 * would; an allocation that starts while that malloc is still running writes "probe: reentrant malloc" and exits 99.
 * Loaded with DYLD_INSERT_LIBRARIES on a Mac (dyld's __interpose) and LD_PRELOAD on Linux (glibc's __libc_* names). */
#define _GNU_SOURCE
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile int inside, armed, count, after = -1, sig;

static void enter(void) {
    if (inside) {
        static const char m[] = "probe: reentrant malloc\n";
        if (write(2, m, sizeof m - 1) < 0) { /* platform: glibc warn_unused_result; nothing to do if stderr is gone */ }
        _exit(99);
    }
    inside = 1;
}
static void probe(void) {
    if (after < 0) {
        const char *a = getenv("RECAULK_PROBE_AFTER"), *s = getenv("RECAULK_PROBE_SIGNAL");
        after = a ? atoi(a) : 0;
        sig = s ? atoi(s) : SIGHUP;
    }
    if (armed && after > 0 && ++count == after) raise(sig);
}

#ifdef __APPLE__
static void *p_malloc(size_t n) { enter(); probe(); void *p = malloc(n); inside = 0; return p; }
static void *p_calloc(size_t k, size_t n) { enter(); probe(); void *p = calloc(k, n); inside = 0; return p; }
static void *p_realloc(void *q, size_t n) { enter(); probe(); void *p = realloc(q, n); inside = 0; return p; }
static char *p_mkdtemp(char *t) { char *r = mkdtemp(t); armed = 1; return r; }
#define INTERPOSE(mine, theirs) \
    __attribute__((used)) static struct { const void *a, *b; } i_##theirs __attribute__((section("__DATA,__interpose"))) = \
        {(const void *)mine, (const void *)theirs}
INTERPOSE(p_malloc, malloc);
INTERPOSE(p_calloc, calloc);
INTERPOSE(p_realloc, realloc);
INTERPOSE(p_mkdtemp, mkdtemp);
#else
#include <dlfcn.h>
extern void *__libc_malloc(size_t), *__libc_calloc(size_t, size_t), *__libc_realloc(void *, size_t);
void *malloc(size_t n) { enter(); probe(); void *p = __libc_malloc(n); inside = 0; return p; }
void *calloc(size_t k, size_t n) { enter(); probe(); void *p = __libc_calloc(k, n); inside = 0; return p; }
void *realloc(void *q, size_t n) { enter(); probe(); void *p = __libc_realloc(q, n); inside = 0; return p; }
char *mkdtemp(char *t) {
    char *(*real)(char *) = (char *(*)(char *))dlsym(RTLD_NEXT, "mkdtemp");
    char *r = real(t);
    armed = 1;
    return r;
}
#endif
