#include <fenv.h>
#include <stdint.h>

#include "libm_exact.h"

#pragma STDC FENV_ACCESS ON

double __recaulk_fma(double a, double b, double c);
double __recaulk_fma_software(double a, double b, double c);
double __recaulk_fma_hardware(double a, double b, double c);
int __recaulk_fma_has_hardware(void);

/* Boldo and Melquiond, "Emulation of FMA and correctly rounded sums: proved algorithms using rounding
 * to odd", IEEE Trans. Computers 57(4), 2008: rounded to odd at 64 bits, then to 53. */
double __recaulk_fma_software(double a, double b, double c) {
    if (!__builtin_isfinite(a) || !__builtin_isfinite(b) || !__builtin_isfinite(c)) {
        if (__builtin_isnan(a) || __builtin_isnan(b)) return a * b + c;
        if (__builtin_isnan(c) || (__builtin_isfinite(a) && __builtin_isfinite(b))) return c + c;
        return a * b + c;
    }
    if (a == 0 || b == 0) return a * b + c;
    if (c == 0) return a * b;
    struct recaulk_exact r;
    if (!__recaulk_libm_exact_sum(__recaulk_libm_from_double(a), __recaulk_libm_from_double(b),
                                  __recaulk_libm_from_double(c), &r))
        return __recaulk_libm_rounding() == RECAULK_DOWNWARD ? -0.0 : 0.0;
    int l, inexact;
    uint64_t q = __recaulk_libm_round64(&r, -(1 << 20), RECAULK_TO_ODD, &l, &inexact);
    union recaulk_ld80 v;
    v.v = 0;
    v.p.m = q;
    v.p.se = (uint16_t)(r.neg << 15 | (l + 63 + 16383));
    return (double)v.v;
}

__attribute__((target("fma"))) double __recaulk_fma_hardware(double a, double b, double c) {
    return __builtin_fma(a, b, c);
}

enum {
    CPUID1_ECX_FMA = 1u << 12,
    CPUID1_ECX_OSXSAVE = 1u << 27,
    CPUID1_ECX_AVX = 1u << 28,
    XCR0_SSE_AND_YMM_STATE = 6
};

int __recaulk_fma_has_hardware(void) {
    static int known = -1;
    int k = __atomic_load_n(&known, __ATOMIC_RELAXED);
    if (k < 0) {
        uint32_t eax, ebx, ecx, edx, lo = 0, hi = 0;
        __asm__ volatile("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(1), "c"(0));
        uint32_t need = CPUID1_ECX_FMA | CPUID1_ECX_OSXSAVE | CPUID1_ECX_AVX;
        k = (ecx & need) == need;
        if (k) {
            __asm__ volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
            k = (lo & XCR0_SSE_AND_YMM_STATE) == XCR0_SSE_AND_YMM_STATE;
        }
        (void)eax, (void)ebx, (void)edx, (void)hi;
        __atomic_store_n(&known, k, __ATOMIC_RELAXED);
    }
    return k;
}

double __recaulk_fma(double a, double b, double c) {
    return __recaulk_fma_has_hardware() ? __recaulk_fma_hardware(a, b, c) : __recaulk_fma_software(a, b, c);
}

__attribute__((weak, visibility("hidden"))) double recaulk_shadow_fma(double, double, double) __asm("_fma");
double recaulk_shadow_fma(double a, double b, double c) { return __recaulk_fma(a, b, c); }
