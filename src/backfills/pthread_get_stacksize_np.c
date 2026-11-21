/*
 * pthread_get_stacksize_np for the main thread, which 10.9 reports as 512 KiB whatever the kernel gave it.
 * README.md "Fixes to functions 10.9 has". It supersedes MacPorts 1.5.2's (build/macports-superseded.txt), which
 * returns RLIMIT_STACK's soft limit as is: that misses the page rounding and an LC_MAIN stacksize.
 *
 * platform: xnu-2422.115.4 bsd/kern/kern_exec.c and mach_loader.c -- the main stack is round_page(the LC_MAIN
 * stacksize) when the executable carries one (Apple ld's -stack_size), else round_page(RLIMIT_STACK's soft limit),
 * which the kernel clamps to MAXSSIZ - PAGE_SIZE. Measured on 10.9.5: a run-time setrlimit moves it too. Every other
 * thread is the system's answer.
 *
 * pthread_get_stacksize_np is a 10.9 export, so here it is weak and hidden (build/image-local-shadows.txt): it binds
 * only inside the image that links librecaulk.a, and yields to the public one src/overrides/pthread_get_stacksize_np_export.c
 * gives libRecaulkSystem.dylib.
 */
#include <crt_externs.h>
#include <dlfcn.h>
#include <mach-o/loader.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/resource.h>

pthread_t pthread_main_thread_np(void);

#define RECAULK_PAGE 4096u
#define RECAULK_MAXSSIZ (64u * 1024 * 1024) /* xnu-2422.115.4 bsd/i386/vmparam.h */

static size_t page_round(uint64_t n) { return (size_t)((n + RECAULK_PAGE - 1) & ~(uint64_t)(RECAULK_PAGE - 1)); }

static uint64_t lc_main_stacksize(void) {
    const struct mach_header_64 *mh = (const struct mach_header_64 *)_NSGetMachExecuteHeader();
    if (!mh || mh->magic != MH_MAGIC_64) return 0;
    const char *p = (const char *)(mh + 1), *end = p + mh->sizeofcmds;
    for (uint32_t i = 0; i < mh->ncmds && p + sizeof(struct load_command) <= end; i++) {
        const struct load_command *lc = (const struct load_command *)(const void *)p;
        if (lc->cmdsize < sizeof *lc || lc->cmdsize > (size_t)(end - p)) return 0;
        if (lc->cmd == LC_MAIN && lc->cmdsize >= sizeof(struct entry_point_command))
            return ((const struct entry_point_command *)(const void *)p)->stacksize;
        p += lc->cmdsize;
    }
    return 0;
}

typedef size_t stacksize_fn(pthread_t);

size_t __recaulk_pthread_get_stacksize_np(pthread_t t);
size_t __recaulk_pthread_get_stacksize_np(pthread_t t) {
    if (pthread_equal(t, pthread_main_thread_np())) {
        uint64_t s = lc_main_stacksize();
        if (s) return page_round(s);
        struct rlimit r;
        if (getrlimit(RLIMIT_STACK, &r) == 0) {
            uint64_t cur = r.rlim_cur;
            if (cur > RECAULK_MAXSSIZ - RECAULK_PAGE) cur = RECAULK_MAXSSIZ - RECAULK_PAGE;
            return page_round(cur);
        }
    }
    static stacksize_fn *system;
    stacksize_fn *f = __atomic_load_n(&system, __ATOMIC_ACQUIRE);
    if (!f) {
        f = (stacksize_fn *)dlsym(RTLD_NEXT, "pthread_get_stacksize_np");
        __atomic_store_n(&system, f, __ATOMIC_RELEASE);
    }
    return f(t);
}

__attribute__((weak, visibility("hidden"))) size_t recaulk_pthread_get_stacksize_np(pthread_t) __asm("_pthread_get_stacksize_np");
__attribute__((weak, visibility("hidden"))) size_t recaulk_pthread_get_stacksize_np(pthread_t t) {
    return __recaulk_pthread_get_stacksize_np(t);
}
