#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static void expect_block(size_t alignment, size_t size) {
    errno = 0;
    unsigned char *p = aligned_alloc(alignment, size);
    if (!p) {
        printf("FAIL: aligned_alloc(%zu, %zu) returned NULL (errno %d)\n", alignment, size, errno);
        failures++;
        return;
    }
    if ((uintptr_t)p % alignment != 0) {
        printf("FAIL: aligned_alloc(%zu, %zu) returned %p, not aligned to %zu\n", alignment, size, (void *)p, alignment);
        failures++;
    }
    memset(p, 0xa5, size);
    free(p);
}

static void expect_error(size_t alignment, size_t size, int want, const char *why) {
    errno = 0;
    void *p = aligned_alloc(alignment, size);
    if (p || errno != want) {
        printf("FAIL: aligned_alloc(%zu, %zu) gave %p with errno %d; %s, so it must give NULL with errno %d\n",
               alignment, size, p, errno, why, want);
        failures++;
        free(p);
    }
}

int main(void) {
    size_t big = (SIZE_MAX / 2) & ~(size_t)4095;
    void *p;

    expect_block(sizeof(void *), sizeof(void *));
    expect_block(16, 16);
    expect_block(16, 48);
    expect_block(64, 64 * 3);
    expect_block(4096, 4096);
    expect_block(1 << 16, 1 << 16);

    expect_error(0, 16, EINVAL, "alignment 0 is no power of two");
    expect_error(3, 3, EINVAL, "alignment 3 is no power of two");
    expect_error(24, 48, EINVAL, "alignment 24 is no power of two");
    expect_error(1, 1, EINVAL, "macOS requires an alignment of at least sizeof(void *)");
    expect_error(4, 8, EINVAL, "macOS requires an alignment of at least sizeof(void *)");
    expect_error(16, 8, EINVAL, "C11 requires the size to be a multiple of the alignment");
    expect_error(16, 24, EINVAL, "C11 requires the size to be a multiple of the alignment");
    expect_error(4096, big, ENOMEM, "no address space holds half of it");

    errno = 0;
    p = aligned_alloc(16, 0);
    if (p && (uintptr_t)p % 16 != 0) {
        printf("FAIL: aligned_alloc(16, 0) returned %p, neither NULL nor aligned\n", p);
        failures++;
    }
    free(p);

    if (failures) return 1;
    printf("aligned_alloc contract OK\n");
    return 0;
}
