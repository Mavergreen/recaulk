/* spec: tests/pthread-main-stacksize-test.sh -- prints the main thread's pthread_get_stacksize_np and the size the
   kernel gave it, then checks that all but 64 KiB of the reported size is usable by recursing through it. */
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>

extern const struct mach_header_64 _mh_execute_header;

static size_t page_round(size_t n) { return (n + 4095) & ~(size_t)4095; }

/* platform: xnu-2422.115.4 bsd/kern/kern_exec.c -- an LC_MAIN stacksize gets round_page(stacksize); otherwise the main
   stack is round_page(RLIMIT_STACK's soft limit), which the kernel clamps to MAXSSIZ - PAGE_SIZE */
static size_t kernel_gave(void) {
    const struct load_command *lc = (const void *)(&_mh_execute_header + 1);
    for (uint32_t i = 0; i < _mh_execute_header.ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize))
        if (lc->cmd == LC_MAIN && ((const struct entry_point_command *)lc)->stacksize)
            return page_round(((const struct entry_point_command *)lc)->stacksize);
    struct rlimit r;
    if (getrlimit(RLIMIT_STACK, &r)) abort();
    return page_round(r.rlim_cur);
}

static volatile char sink;
static void use(size_t left) {
    char frame[16384];
    memset(frame, 1, sizeof frame);
    sink = frame[left % sizeof frame];
    if (left > sizeof frame + 512) use(left - sizeof frame - 512);
    sink = frame[0];
}

int main(void) {
    size_t got = pthread_get_stacksize_np(pthread_self()), want = kernel_gave();
    printf("reported %zu, kernel gave %zu\n", got, want);
    if (got != want) { puts("FAIL: the main thread's size is not what the kernel gave it"); return 1; }
    use(got - 65536);
    puts("ok: used all but 64 KiB of it");
    return 0;
}
