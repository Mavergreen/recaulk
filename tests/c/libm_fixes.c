#include <fenv.h>
#include <float.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "libm_cases.h"

#pragma STDC FENV_ACCESS ON

static double (*volatile fma_p)(double, double, double) = fma;
static float (*volatile fmaf_p)(float, float, float) = fmaf;
static long double (*volatile fmal_p)(long double, long double, long double) = fmal;
static double (*volatile trunc_p)(double) = trunc;
static float (*volatile truncf_p)(float) = truncf;
static long double (*volatile truncl_p)(long double) = truncl;

static const int modes[4] = {FE_TONEAREST, FE_TOWARDZERO, FE_UPWARD, FE_DOWNWARD};
static const char *const mode_names[4] = {"to nearest", "toward zero", "upward", "downward"};
static int failures;
static const char *const fn_names[] = {"fma", "fmaf", "fmal", "trunc", "truncf", "truncl"};
static int fn_failures[6];

union f80 {
    long double v;
    struct ld_bits b;
};

static float f32(unsigned u) { float f; memcpy(&f, &u, sizeof f); return f; }
static unsigned u32(float f) { unsigned u; memcpy(&u, &f, sizeof u); return u; }
static double f64(unsigned long long u) { double d; memcpy(&d, &u, sizeof d); return d; }
static unsigned long long u64(double d) { unsigned long long u; memcpy(&u, &d, sizeof u); return u; }
static long double f80(struct ld_bits b) { union f80 x; memset(&x, 0, sizeof x); x.b = b; return x.v; }
static int same80(long double v, struct ld_bits want) {
    union f80 x; memset(&x, 0, sizeof x); x.v = v;
    return x.b.m == want.m && x.b.se == want.se;
}

static void fail(const char *what) {
    size_t n = strcspn(what, "(");
    for (unsigned i = 0; i < 6; i++)
        if (strlen(fn_names[i]) == n && strncmp(what, fn_names[i], n) == 0) fn_failures[i]++;
    if (++failures <= 60) printf("FAIL: %s\n", what);
}

static void vectors(void) {
    char line[512];
    for (unsigned m = 0; m < 4; m++) {
        fesetround(modes[m]);
        for (unsigned i = 0; i < sizeof f32_cases / sizeof *f32_cases; i++) {
            const struct f32_case *k = &f32_cases[i];
            float r = fmaf_p(f32(k->a), f32(k->b), f32(k->c));
            if (u32(r) == k->r[m]) continue;
            snprintf(line, sizeof line, "fmaf(%a, %a, %a) rounded %s is %a, want %a", f32(k->a), f32(k->b),
                     f32(k->c), mode_names[m], r, f32(k->r[m]));
            fail(line);
        }
        for (unsigned i = 0; i < sizeof f64_cases / sizeof *f64_cases; i++) {
            const struct f64_case *k = &f64_cases[i];
            double r = fma_p(f64(k->a), f64(k->b), f64(k->c));
            if (u64(r) == k->r[m]) continue;
            snprintf(line, sizeof line, "fma(%a, %a, %a) rounded %s is %a, want %a", f64(k->a), f64(k->b),
                     f64(k->c), mode_names[m], r, f64(k->r[m]));
            fail(line);
        }
        for (unsigned i = 0; i < sizeof f80_cases / sizeof *f80_cases; i++) {
            const struct f80_case *k = &f80_cases[i];
            long double r = fmal_p(f80(k->a), f80(k->b), f80(k->c));
            if (same80(r, k->r[m])) continue;
            snprintf(line, sizeof line, "fmal(%La, %La, %La) rounded %s is %La, want %La", f80(k->a),
                     f80(k->b), f80(k->c), mode_names[m], r, f80(k->r[m]));
            fail(line);
        }
    }
    fesetround(FE_TONEAREST);
}

#define EXPECT(name, call, want)                                                                          \
    do {                                                                                                  \
        long double got_ = (call), want_ = (want);                                                        \
        if (!(isnan(want_) ? isnan(got_) : got_ == want_ && signbit(got_) == signbit(want_))) {           \
            snprintf(line, sizeof line, "%s rounded %s is %La, want %La", name, mode_names[m], got_, want_); \
            fail(line);                                                                                   \
        }                                                                                                 \
    } while (0)

static void specials(void) {
    char line[512];
    const double inf = INFINITY, nan = NAN;
    const long double infl = INFINITY;
    for (unsigned m = 0; m < 4; m++) {
        const int down = modes[m] == FE_DOWNWARD;
        fesetround(modes[m]);
        EXPECT("fma(inf, 0, nan)", fma_p(inf, 0, nan), nan);
        EXPECT("fma(inf, 0, 1)", fma_p(inf, 0, 1), nan);
        EXPECT("fma(inf, 1, -inf)", fma_p(inf, 1, -inf), nan);
        EXPECT("fma(nan, 1, 1)", fma_p(nan, 1, 1), nan);
        EXPECT("fma(1, nan, inf)", fma_p(1, nan, inf), nan);
        EXPECT("fma(1, 1, inf)", fma_p(1, 1, inf), inf);
        EXPECT("fma(-inf, 2, -inf)", fma_p(-inf, 2, -inf), -inf);
        EXPECT("fma(DBL_MAX, 2, -inf)", fma_p(DBL_MAX, 2, -inf), -inf);
        EXPECT("fma(DBL_MAX, DBL_MAX, -inf)", fma_p(DBL_MAX, DBL_MAX, -inf), -inf);
        EXPECT("fma(+0, -1, +0)", fma_p(0.0, -1, 0.0), down ? -0.0 : 0.0);
        EXPECT("fma(-0, 1, -0)", fma_p(-0.0, 1, -0.0), -0.0);
        EXPECT("fma(-0, -1, -0)", fma_p(-0.0, -1, -0.0), down ? -0.0 : 0.0);
        EXPECT("fma(0x1p-600, -0x1p-600, +0)", fma_p(0x1p-600, -0x1p-600, 0.0), down ? -0x1p-1074 : -0.0);
        EXPECT("fma(0x1p-600, 0x1p-600, -0)", fma_p(0x1p-600, 0x1p-600, -0.0), modes[m] == FE_UPWARD ? 0x1p-1074 : 0.0);
        EXPECT("fma(0x1p-600, 0x1p-600, 0x1p-1074)", fma_p(0x1p-600, 0x1p-600, 0x1p-1074),
               modes[m] == FE_UPWARD ? 0x1p-1073 : 0x1p-1074);

        EXPECT("fmaf(inf, 0, nan)", fmaf_p(INFINITY, 0, NAN), NAN);
        EXPECT("fmaf(inf, 0, 1)", fmaf_p(INFINITY, 0, 1), NAN);
        EXPECT("fmaf(FLT_MAX, 2, -inf)", fmaf_p(FLT_MAX, 2, -INFINITY), -INFINITY);
        EXPECT("fmaf(+0, -1, +0)", fmaf_p(0.0f, -1, 0.0f), down ? -0.0f : 0.0f);
        EXPECT("fmaf(-0, 1, -0)", fmaf_p(-0.0f, 1, -0.0f), -0.0f);
        EXPECT("fmaf(0x1p-80, -0x1p-80, +0)", fmaf_p(0x1p-80f, -0x1p-80f, 0.0f), down ? -0x1p-149f : -0.0f);
        EXPECT("fmaf(0x1p-80, 0x1p-80, 0x1p-149)", fmaf_p(0x1p-80f, 0x1p-80f, 0x1p-149f),
               modes[m] == FE_UPWARD ? 0x1p-148f : 0x1p-149f);

        EXPECT("fmal(inf, 0, nan)", fmal_p(infl, 0, NAN), (long double)NAN);
        EXPECT("fmal(inf, 0, 1)", fmal_p(infl, 0, 1), (long double)NAN);
        EXPECT("fmal(inf, 1, -inf)", fmal_p(infl, 1, -infl), (long double)NAN);
        EXPECT("fmal(1, 1, nan)", fmal_p(1, 1, NAN), (long double)NAN);
        EXPECT("fmal(1, 1, inf)", fmal_p(1, 1, infl), infl);
        EXPECT("fmal(LDBL_MAX, 2, -inf)", fmal_p(LDBL_MAX, 2, -infl), -infl);
        EXPECT("fmal(+0, -1, +0)", fmal_p(0.0L, -1, 0.0L), down ? -0.0L : 0.0L);
        EXPECT("fmal(-0, 1, -0)", fmal_p(-0.0L, 1, -0.0L), -0.0L);
        EXPECT("fmal(0x1p-8300, -0x1p-8300, +0)", fmal_p(0x1p-8300L, -0x1p-8300L, 0.0L),
               down ? -0x1p-16445L : -0.0L);
        EXPECT("fmal(0x1p-8300, 0x1p-8300, -0)", fmal_p(0x1p-8300L, 0x1p-8300L, -0.0L),
               modes[m] == FE_UPWARD ? 0x1p-16445L : 0.0L);
        EXPECT("fmal(0x1p-8300, 0x1p-8300, 0x1p-16445)", fmal_p(0x1p-8300L, 0x1p-8300L, 0x1p-16445L),
               modes[m] == FE_UPWARD ? 0x1p-16444L : 0x1p-16445L);
        EXPECT("fmal(0x1p8192, 0x1p8192, -LDBL_MAX)", fmal_p(0x1p8192L, 0x1p8192L, -LDBL_MAX), 0x1p16320L);
    }
    fesetround(FE_TONEAREST);
}

static void truncs(void) {
    char line[512];
    const unsigned m = 0;
    static const long double in[] = {0.0L, -0.0L, 0.5L, -0.5L, 0x1.fffffffffffffffep-1L, -0x1.fffffffffffffffep-1L,
                                     0x1p-16445L, -0x1p-16445L, 1.5L, -1.5L, -1.0L, 0x1.fffffffffffffffep62L,
                                     -0x1.fffffffffffffffep62L, 0x1p63L, -0x1p64L, -0x1.8p100L, INFINITY, -INFINITY};
    for (unsigned i = 0; i < sizeof in / sizeof *in; i++) {
        long double x = in[i];
        long double want = fabsl(x) < 1 ? copysignl(0.0L, x) : x;
        if (fabsl(x) >= 1 && fabsl(x) < 0x1p63L) want = (long double)(long long)x;
        snprintf(line, sizeof line, "truncl(%La)", x);
        EXPECT(line, truncl_p(x), want);
        if (fabsl(x) <= DBL_MAX && (x == 0 || fabsl(x) >= DBL_MIN)) {
            double d = (double)x;
            double wd = fabs(d) < 1 ? copysign(0.0, d) : fabs(d) < 0x1p52 ? (double)(long long)d : d;
            snprintf(line, sizeof line, "trunc(%a)", d);
            EXPECT(line, trunc_p(d), wd);
        }
        if (fabsl(x) <= FLT_MAX && (x == 0 || fabsl(x) >= FLT_MIN)) {
            float f = (float)x;
            float wf = fabsf(f) < 1 ? copysignf(0.0f, f) : fabsf(f) < 0x1p23f ? (float)(long long)f : f;
            snprintf(line, sizeof line, "truncf(%a)", f);
            EXPECT(line, truncf_p(f), wf);
        }
    }
    EXPECT("truncl(nan)", truncl_p(NAN), (long double)NAN);
    EXPECT("trunc(nan)", trunc_p(NAN), (double)NAN);
    EXPECT("truncf(nan)", truncf_p(NAN), (float)NAN);
}

int main(void) {
    vectors();
    specials();
    truncs();
    if (failures) {
        for (unsigned i = 0; i < 6; i++)
            if (fn_failures[i]) printf("FAIL: %s: %d wrong results\n", fn_names[i], fn_failures[i]);
        return 1;
    }
    printf("ok libm-fixes\n");
    return 0;
}
