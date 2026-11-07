#include <fenv.h>
#include <stdint.h>

#include "libm_exact.h"

#pragma STDC FENV_ACCESS ON

long double __recaulk_fmal(long double a, long double b, long double c);

long double __recaulk_fmal(long double a, long double b, long double c) {
    if (!__builtin_isfinite(a) || !__builtin_isfinite(b) || !__builtin_isfinite(c)) {
        if (__builtin_isfinite(a) && __builtin_isfinite(b)) return c + c;
        return a * b + c;
    }
    if (a == 0 || b == 0) return a * b + c;
    if (c == 0) return a * b;
    enum recaulk_rounding mode = __recaulk_libm_rounding();
    struct recaulk_exact r;
    if (!__recaulk_libm_exact_sum(__recaulk_libm_from_ld(a), __recaulk_libm_from_ld(b), __recaulk_libm_from_ld(c), &r))
        return mode == RECAULK_DOWNWARD ? -0.0L : 0.0L;
    int l, inexact;
    uint64_t q = __recaulk_libm_round64(&r, -16445, mode, &l, &inexact);
    union recaulk_ld80 v;
    v.v = 0;
    if (l > 16383 - 63) {
        feraiseexcept(FE_OVERFLOW | FE_INEXACT);
        if (mode == RECAULK_NEAREST || (mode == RECAULK_UPWARD && !r.neg) || (mode == RECAULK_DOWNWARD && r.neg)) {
            v.p.m = UINT64_C(1) << 63;
            v.p.se = (uint16_t)(r.neg << 15 | 0x7fff);
        } else {
            v.p.m = ~UINT64_C(0);
            v.p.se = (uint16_t)(r.neg << 15 | 0x7ffe);
        }
        return v.v;
    }
    if (inexact) {
        int unbounded_lsb, unused;
        __recaulk_libm_round64(&r, -(1 << 20), mode, &unbounded_lsb, &unused);
        feraiseexcept(unbounded_lsb + 63 < -16382 ? FE_UNDERFLOW | FE_INEXACT : FE_INEXACT);
    }
    v.p.m = q;
    v.p.se = (uint16_t)(r.neg << 15 | (q >> 63 ? l + 63 + 16383 : 0));
    return v.v;
}

__attribute__((weak, visibility("hidden"))) long double recaulk_shadow_fmal(long double, long double, long double)
    __asm("_fmal");
long double recaulk_shadow_fmal(long double a, long double b, long double c) { return __recaulk_fmal(a, b, c); }
