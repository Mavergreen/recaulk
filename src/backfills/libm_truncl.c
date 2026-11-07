#include <stdint.h>

#include "libm_exact.h"

long double __recaulk_truncl(long double x);

long double __recaulk_truncl(long double x) {
    union recaulk_ld80 v;
    v.v = x;
    int e = (v.p.se & 0x7fff) - 16383;
    if (e >= 63) return x != x ? x + x : x;
    if (e < 0) {
        v.p.m = 0;
        v.p.se &= 0x8000;
    } else {
        v.p.m &= ~((UINT64_C(1) << (63 - e)) - 1);
    }
    return v.v;
}

__attribute__((weak, visibility("hidden"))) long double recaulk_shadow_truncl(long double) __asm("_truncl");
long double recaulk_shadow_truncl(long double x) { return __recaulk_truncl(x); }
