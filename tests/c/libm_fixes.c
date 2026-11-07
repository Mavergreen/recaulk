#include <fenv.h>
#include <float.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "libm_cases.h"

#pragma STDC FENV_ACCESS ON

#ifdef RECAULK_FMA_PATHS
double __recaulk_fma_software(double a, double b, double c);
double __recaulk_fma_hardware(double a, double b, double c);
int __recaulk_fma_has_hardware(void);
#endif

typedef double fma_fn(double, double, double);

static struct {
    const char *name;
    fma_fn *fn;
} fmas[3] = {{"fma", fma}};
static unsigned nfmas = 1;
static float (*volatile fmaf_p)(float, float, float) = fmaf;
static long double (*volatile fmal_p)(long double, long double, long double) = fmal;
static double (*volatile trunc_p)(double) = trunc;
static float (*volatile truncf_p)(float) = truncf;
static long double (*volatile truncl_p)(long double) = truncl;

static const int modes[4] = {FE_TONEAREST, FE_TOWARDZERO, FE_UPWARD, FE_DOWNWARD};
static const char *const mode_names[4] = {"to nearest", "toward zero", "upward", "downward"};
static const int watched = FE_INEXACT | FE_UNDERFLOW | FE_OVERFLOW | FE_INVALID;
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

static int fe_of(unsigned char e) {
    return (e & 1 ? FE_INEXACT : 0) | (e & 2 ? FE_UNDERFLOW : 0) | (e & 4 ? FE_OVERFLOW : 0);
}

static const char *flag_names(int f) {
    static char s[4][64];
    static unsigned next;
    char *p = s[next++ % 4];
    snprintf(p, 64, "{%s%s%s%s }", f & FE_INEXACT ? " inexact" : "", f & FE_UNDERFLOW ? " underflow" : "",
             f & FE_OVERFLOW ? " overflow" : "", f & FE_INVALID ? " invalid" : "");
    return p;
}

static void fail(const char *what) {
    size_t n = strcspn(what, "(");
    for (unsigned i = 0; i < 6; i++)
        if (strlen(fn_names[i]) == n && strncmp(what, fn_names[i], n) == 0) fn_failures[i]++;
    if (++failures <= 60) printf("FAIL: %s\n", what);
}

#define CALL(result, flags, call)                                                                         \
    do {                                                                                                  \
        feclearexcept(FE_ALL_EXCEPT);                                                                     \
        result = (call);                                                                                  \
        flags = fetestexcept(watched);                                                                    \
    } while (0)

static void vectors(void) {
    char line[640];
    for (unsigned m = 0; m < 4; m++) {
        fesetround(modes[m]);
        for (unsigned i = 0; i < sizeof f32_cases / sizeof *f32_cases; i++) {
            const struct f32_case *k = &f32_cases[i];
            float r;
            int fl;
            CALL(r, fl, fmaf_p(f32(k->a), f32(k->b), f32(k->c)));
            if (u32(r) == k->r[m] && fl == fe_of(k->e[m])) continue;
            snprintf(line, sizeof line, "fmaf(%a, %a, %a) rounded %s is %a %s, want %a %s", f32(k->a),
                     f32(k->b), f32(k->c), mode_names[m], r, flag_names(fl), f32(k->r[m]),
                     flag_names(fe_of(k->e[m])));
            fail(line);
        }
        for (unsigned j = 0; j < nfmas; j++) {
            fma_fn *volatile fn = fmas[j].fn;
            for (unsigned i = 0; i < sizeof f64_cases / sizeof *f64_cases; i++) {
                const struct f64_case *k = &f64_cases[i];
                double r;
                int fl;
                CALL(r, fl, fn(f64(k->a), f64(k->b), f64(k->c)));
                if (u64(r) == k->r[m] && fl == fe_of(k->e[m])) continue;
                snprintf(line, sizeof line, "%s(%a, %a, %a) rounded %s is %a %s, want %a %s", fmas[j].name,
                         f64(k->a), f64(k->b), f64(k->c), mode_names[m], r, flag_names(fl), f64(k->r[m]),
                         flag_names(fe_of(k->e[m])));
                fail(line);
            }
        }
        for (unsigned i = 0; i < sizeof f80_cases / sizeof *f80_cases; i++) {
            const struct f80_case *k = &f80_cases[i];
            long double r;
            int fl;
            CALL(r, fl, fmal_p(f80(k->a), f80(k->b), f80(k->c)));
            if (same80(r, k->r[m]) && fl == fe_of(k->e[m])) continue;
            snprintf(line, sizeof line, "fmal(%La, %La, %La) rounded %s is %La %s, want %La %s", f80(k->a),
                     f80(k->b), f80(k->c), mode_names[m], r, flag_names(fl), f80(k->r[m]),
                     flag_names(fe_of(k->e[m])));
            fail(line);
        }
    }
    fesetround(FE_TONEAREST);
}

#define EXPECT(name, call, want, want_flags)                                                              \
    do {                                                                                                  \
        long double got_, want_ = (want);                                                                 \
        int fl_;                                                                                          \
        CALL(got_, fl_, call);                                                                            \
        if (!(isnan(want_) ? isnan(got_) : got_ == want_ && signbit(got_) == signbit(want_)) ||          \
            fl_ != (want_flags)) {                                                                        \
            snprintf(line, sizeof line, "%s rounded %s is %La %s, want %La %s", name, mode_names[m], got_,  \
                     flag_names(fl_), want_, flag_names(want_flags));                                     \
            fail(line);                                                                                   \
        }                                                                                                 \
    } while (0)

static void fma_specials(fma_fn *volatile f, const char *fn) {
    char line[640], name[160];
    const double inf = INFINITY, nan = NAN, snan = f64(0x7ff0000000000001ULL);
    for (unsigned m = 0; m < 4; m++) {
        const int down = modes[m] == FE_DOWNWARD, up = modes[m] == FE_UPWARD;
        const int to_inf = modes[m] == FE_TONEAREST || up;
        fesetround(modes[m]);
#define FMA(a, b, c, want, flags)                                                                         \
    do {                                                                                                  \
        snprintf(name, sizeof name, "%s(%s, %s, %s)", fn, #a, #b, #c);                                    \
        EXPECT(name, f(a, b, c), want, flags);                                                            \
    } while (0)
        FMA(inf, 0, nan, nan, 0);
        FMA(0, -inf, nan, nan, 0);
        FMA(inf, 0, snan, nan, FE_INVALID);
        FMA(1, 1, snan, nan, FE_INVALID);
        FMA(inf, 0, 1, nan, FE_INVALID);
        FMA(inf, 1, -inf, nan, FE_INVALID);
        FMA(nan, 1, 1, nan, 0);
        FMA(1, nan, inf, nan, 0);
        FMA(1, 1, inf, inf, 0);
        FMA(-inf, 2, -inf, -inf, 0);
        FMA(DBL_MAX, 2, -inf, -inf, 0);
        FMA(DBL_MAX, DBL_MAX, -inf, -inf, 0);
        FMA(DBL_MAX, 2, -1, to_inf ? inf : DBL_MAX, FE_OVERFLOW | FE_INEXACT);
        FMA(2, 3, 1, 7, 0);
        FMA(2, 3, -6, down ? -0.0 : 0.0, 0);
        FMA(0.0, -1, 0.0, down ? -0.0 : 0.0, 0);
        FMA(-0.0, 1, -0.0, -0.0, 0);
        FMA(-0.0, -1, -0.0, down ? -0.0 : 0.0, 0);
        FMA(1 + DBL_EPSILON, 1 + DBL_EPSILON, -1, up ? 0x1.0000000000001p-51 : 0x1p-51, FE_INEXACT);
        FMA(0x1p-600, -0x1p-600, 0.0, down ? -0x1p-1074 : -0.0, FE_UNDERFLOW | FE_INEXACT);
        FMA(0x1p-600, 0x1p-600, -0.0, up ? 0x1p-1074 : 0.0, FE_UNDERFLOW | FE_INEXACT);
        FMA(0x1p-600, 0x1p-600, 0x1p-1074, up ? 0x1p-1073 : 0x1p-1074, FE_UNDERFLOW | FE_INEXACT);
        FMA(0x1p-1022, 0.5, 0x1p-1074, 0x1.0000000000002p-1023, 0);
#undef FMA
    }
    fesetround(FE_TONEAREST);
}

static void specials(void) {
    char line[640];
    const long double infl = INFINITY;
    const long double snanl = f80((struct ld_bits){0x8000000000000001ULL, 0x7fff});
    for (unsigned j = 0; j < nfmas; j++) fma_specials(fmas[j].fn, fmas[j].name);
    for (unsigned m = 0; m < 4; m++) {
        const int down = modes[m] == FE_DOWNWARD, up = modes[m] == FE_UPWARD;
        const int to_inf = modes[m] == FE_TONEAREST || up;
        fesetround(modes[m]);
        EXPECT("fmaf(inf, 0, nan)", fmaf_p(INFINITY, 0, NAN), NAN, 0);
        EXPECT("fmaf(inf, 0, 1)", fmaf_p(INFINITY, 0, 1), NAN, FE_INVALID);
        EXPECT("fmaf(FLT_MAX, 2, -inf)", fmaf_p(FLT_MAX, 2, -INFINITY), -INFINITY, 0);
        EXPECT("fmaf(+0, -1, +0)", fmaf_p(0.0f, -1, 0.0f), down ? -0.0f : 0.0f, 0);
        EXPECT("fmaf(-0, 1, -0)", fmaf_p(-0.0f, 1, -0.0f), -0.0f, 0);
        EXPECT("fmaf(0x1p-80, -0x1p-80, +0)", fmaf_p(0x1p-80f, -0x1p-80f, 0.0f), down ? -0x1p-149f : -0.0f,
               FE_UNDERFLOW | FE_INEXACT);
        EXPECT("fmaf(0x1p-80, 0x1p-80, 0x1p-149)", fmaf_p(0x1p-80f, 0x1p-80f, 0x1p-149f),
               up ? 0x1p-148f : 0x1p-149f, FE_UNDERFLOW | FE_INEXACT);

        EXPECT("fmal(inf, 0, nan)", fmal_p(infl, 0, NAN), (long double)NAN, 0);
        EXPECT("fmal(0, -inf, nan)", fmal_p(0, -infl, NAN), (long double)NAN, 0);
        EXPECT("fmal(inf, 0, snan)", fmal_p(infl, 0, snanl), (long double)NAN, FE_INVALID);
        EXPECT("fmal(1, 1, snan)", fmal_p(1, 1, snanl), (long double)NAN, FE_INVALID);
        EXPECT("fmal(inf, 0, 1)", fmal_p(infl, 0, 1), (long double)NAN, FE_INVALID);
        EXPECT("fmal(inf, 1, -inf)", fmal_p(infl, 1, -infl), (long double)NAN, FE_INVALID);
        EXPECT("fmal(1, 1, nan)", fmal_p(1, 1, NAN), (long double)NAN, 0);
        EXPECT("fmal(1, 1, inf)", fmal_p(1, 1, infl), infl, 0);
        EXPECT("fmal(LDBL_MAX, 2, -inf)", fmal_p(LDBL_MAX, 2, -infl), -infl, 0);
        EXPECT("fmal(LDBL_MAX, 2, -1)", fmal_p(LDBL_MAX, 2, -1), to_inf ? infl : LDBL_MAX,
               FE_OVERFLOW | FE_INEXACT);
        EXPECT("fmal(0x1p8192, 0x1p8192, 0)", fmal_p(0x1p8192L, 0x1p8192L, 0), to_inf ? infl : LDBL_MAX,
               FE_OVERFLOW | FE_INEXACT);
        EXPECT("fmal(2, 3, 1)", fmal_p(2, 3, 1), 7.0L, 0);
        EXPECT("fmal(2, 3, -6)", fmal_p(2, 3, -6), down ? -0.0L : 0.0L, 0);
        EXPECT("fmal(+0, -1, +0)", fmal_p(0.0L, -1, 0.0L), down ? -0.0L : 0.0L, 0);
        EXPECT("fmal(-0, 1, -0)", fmal_p(-0.0L, 1, -0.0L), -0.0L, 0);
        EXPECT("fmal(1+eps, 1+eps, -1)", fmal_p(1 + LDBL_EPSILON, 1 + LDBL_EPSILON, -1),
               up ? 0x1.0000000000000002p-62L : 0x1p-62L, FE_INEXACT);
        EXPECT("fmal(0x1p-8300, -0x1p-8300, +0)", fmal_p(0x1p-8300L, -0x1p-8300L, 0.0L),
               down ? -0x1p-16445L : -0.0L, FE_UNDERFLOW | FE_INEXACT);
        EXPECT("fmal(0x1p-8300, 0x1p-8300, -0)", fmal_p(0x1p-8300L, 0x1p-8300L, -0.0L), up ? 0x1p-16445L : 0.0L,
               FE_UNDERFLOW | FE_INEXACT);
        EXPECT("fmal(0x1p-8300, 0x1p-8300, 0x1p-16445)", fmal_p(0x1p-8300L, 0x1p-8300L, 0x1p-16445L),
               up ? 0x1p-16444L : 0x1p-16445L, FE_UNDERFLOW | FE_INEXACT);
        EXPECT("fmal(0x1p8192, 0x1p8192, -LDBL_MAX)", fmal_p(0x1p8192L, 0x1p8192L, -LDBL_MAX), 0x1p16320L, 0);
        if (modes[m] == FE_TONEAREST)
            EXPECT("fmal(0x1.0000000000000008p-16382, 0x1.fffffffffffffffcp-1, -0x1.8p-16444)",
                   fmal_p(0x1.0000000000000008p-16382L, 0x1.fffffffffffffffcp-1L, -0x1.8p-16444L), 0x1p-16382L,
                   FE_INEXACT);
    }
    fesetround(FE_TONEAREST);
}

static void truncs(void) {
    char line[640];
    const unsigned m = 0;
    static const long double in[] = {0.0L, -0.0L, 0.5L, -0.5L, 0x1.fffffffffffffffep-1L, -0x1.fffffffffffffffep-1L,
                                     0x1p-16445L, -0x1p-16445L, 1.5L, -1.5L, -1.0L, 0x1.fffffffffffffffep62L,
                                     -0x1.fffffffffffffffep62L, 0x1p63L, -0x1p64L, -0x1.8p100L, INFINITY, -INFINITY};
    for (unsigned i = 0; i < sizeof in / sizeof *in; i++) {
        long double x = in[i];
        long double want = fabsl(x) < 1 ? copysignl(0.0L, x) : x;
        char name[96];
        if (fabsl(x) >= 1 && fabsl(x) < 0x1p63L) want = (long double)(long long)x;
        snprintf(name, sizeof name, "truncl(%La)", x);
        EXPECT(name, truncl_p(x), want, 0);
        if (fabsl(x) <= DBL_MAX && (x == 0 || fabsl(x) >= DBL_MIN)) {
            double d = (double)x;
            double wd = fabs(d) < 1 ? copysign(0.0, d) : fabs(d) < 0x1p52 ? (double)(long long)d : d;
            long double got = trunc_p(d), wl = wd;
            if (!(got == wl && signbit(got) == signbit(wl))) {
                snprintf(line, sizeof line, "trunc(%a) is %La, want %La", d, got, wl);
                fail(line);
            }
        }
        if (fabsl(x) <= FLT_MAX && (x == 0 || fabsl(x) >= FLT_MIN)) {
            float f = (float)x;
            float wf = fabsf(f) < 1 ? copysignf(0.0f, f) : fabsf(f) < 0x1p23f ? (float)(long long)f : f;
            long double got = truncf_p(f), wl = wf;
            if (!(got == wl && signbit(got) == signbit(wl))) {
                snprintf(line, sizeof line, "truncf(%a) is %La, want %La", f, got, wl);
                fail(line);
            }
        }
    }
    EXPECT("truncl(nan)", truncl_p(NAN), (long double)NAN, 0);
    if (!isnan(trunc_p(NAN))) fail("trunc(nan) is not NaN");
    if (!isnan(truncf_p(NAN))) fail("truncf(nan) is not NaN");
}

int main(void) {
#ifdef RECAULK_FMA_PATHS
    fmas[nfmas].name = "fma_software";
    fmas[nfmas++].fn = __recaulk_fma_software;
    if (__recaulk_fma_has_hardware()) {
        fmas[nfmas].name = "fma_hardware";
        fmas[nfmas++].fn = __recaulk_fma_hardware;
        printf("fma: this CPU has FMA; fma, its software path and its hardware path tested\n");
    } else {
        printf("fma: this CPU has no FMA; fma and its software path tested\n");
    }
#endif
    vectors();
    specials();
    truncs();
    if (failures) {
        for (unsigned i = 0; i < 6; i++)
            if (fn_failures[i]) printf("FAIL: %s: %d wrong results\n", fn_names[i], fn_failures[i]);
        printf("FAIL: %d wrong results in all\n", failures);
        return 1;
    }
    printf("ok libm-fixes\n");
    return 0;
}
