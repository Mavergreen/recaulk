#include <fenv.h>
#include <stdint.h>

#pragma STDC FENV_ACCESS ON

double __recaulk_fma(double a, double b, double c);
long double __recaulk_fmal(long double a, long double b, long double c);
long double __recaulk_truncl(long double x);

typedef unsigned __int128 u128;

enum rounding { NEAREST, TOWARD_ZERO, UPWARD, DOWNWARD, TO_ODD };

struct operand {
    int neg, exp;
    uint64_t m;
};

struct wide {
    uint64_t w[3];
};

union ld80 {
    long double v;
    struct {
        uint64_t m;
        uint16_t se;
    } p;
};

static enum rounding current_rounding(void) {
    switch (fegetround()) {
    case FE_TOWARDZERO: return TOWARD_ZERO;
    case FE_UPWARD: return UPWARD;
    case FE_DOWNWARD: return DOWNWARD;
    default: return NEAREST;
    }
}

static struct operand from_double(double x) {
    union {
        double d;
        uint64_t u;
    } v = {x};
    struct operand o;
    int e = (int)(v.u >> 52 & 0x7ff);
    o.neg = (int)(v.u >> 63);
    o.m = v.u & ((UINT64_C(1) << 52) - 1);
    if (e) o.m |= UINT64_C(1) << 52;
    o.exp = (e ? e : 1) - 1075;
    return o;
}

static struct operand from_ld(long double x) {
    union ld80 v;
    struct operand o;
    v.v = x;
    int e = v.p.se & 0x7fff;
    o.neg = v.p.se >> 15;
    o.m = v.p.m;
    o.exp = (e ? e : 1) - 16383 - 63;
    return o;
}

static int top(const struct wide *n) {
    for (int i = 2; i >= 0; i--)
        if (n->w[i]) return 64 * i + 63 - __builtin_clzll(n->w[i]);
    return -1;
}

static void shift_left(struct wide *n, int s) {
    while (s >= 64) {
        n->w[2] = n->w[1];
        n->w[1] = n->w[0];
        n->w[0] = 0;
        s -= 64;
    }
    if (s) {
        n->w[2] = n->w[2] << s | n->w[1] >> (64 - s);
        n->w[1] = n->w[1] << s | n->w[0] >> (64 - s);
        n->w[0] <<= s;
    }
}

static int shift_right(struct wide *n, int s) {
    int lost = 0;
    if (s >= 192) {
        lost = n->w[0] || n->w[1] || n->w[2];
        n->w[0] = n->w[1] = n->w[2] = 0;
        return lost;
    }
    while (s >= 64) {
        lost |= n->w[0] != 0;
        n->w[0] = n->w[1];
        n->w[1] = n->w[2];
        n->w[2] = 0;
        s -= 64;
    }
    if (s) {
        lost |= (n->w[0] << (64 - s)) != 0;
        n->w[0] = n->w[0] >> s | n->w[1] << (64 - s);
        n->w[1] = n->w[1] >> s | n->w[2] << (64 - s);
        n->w[2] >>= s;
    }
    return lost;
}

static int less(const struct wide *x, const struct wide *y) {
    for (int i = 2; i >= 0; i--)
        if (x->w[i] != y->w[i]) return x->w[i] < y->w[i];
    return 0;
}

static void add(struct wide *x, const struct wide *y) {
    uint64_t carry = 0;
    for (int i = 0; i < 3; i++) {
        u128 s = (u128)x->w[i] + y->w[i] + carry;
        x->w[i] = (uint64_t)s;
        carry = (uint64_t)(s >> 64);
    }
}

static void subtract(struct wide *x, const struct wide *y, int extra) {
    uint64_t borrow = (uint64_t)extra;
    for (int i = 0; i < 3; i++) {
        u128 d = (u128)x->w[i] - y->w[i] - borrow;
        x->w[i] = (uint64_t)d;
        borrow = (uint64_t)(d >> 64) & 1;
    }
}

struct exact {
    int neg, exp, sticky;
    struct wide n;
};

static int exact_sum(struct operand a, struct operand b, struct operand c, struct exact *r) {
    u128 p = (u128)a.m * b.m;
    struct wide x = {{(uint64_t)p, (uint64_t)(p >> 64), 0}}, y = {{c.m, 0, 0}};
    int xneg = a.neg ^ b.neg, yneg = c.neg;
    int tx = top(&x), ty = top(&y);
    int topx = a.exp + b.exp + tx, topy = c.exp + ty;
    if (topy > topx) {
        struct wide w = x;
        x = y;
        y = w;
        int t = tx;
        tx = ty;
        ty = t;
        t = topx;
        topx = topy;
        topy = t;
        t = xneg;
        xneg = yneg;
        yneg = t;
    }
    shift_left(&x, 189 - tx);
    int s = 189 - (topx - topy) - ty, sticky = 0;
    if (s >= 0)
        shift_left(&y, s);
    else
        sticky = shift_right(&y, -s);
    if (xneg == yneg) {
        add(&x, &y);
    } else {
        if (less(&x, &y)) {
            struct wide w = x;
            x = y;
            y = w;
            xneg = yneg;
        }
        subtract(&x, &y, sticky);
    }
    if (!sticky && !x.w[0] && !x.w[1] && !x.w[2]) return 0;
    r->neg = xneg;
    r->exp = topx - 189;
    r->sticky = sticky;
    r->n = x;
    return 1;
}

static uint64_t round64(const struct exact *r, int lsb_min, enum rounding mode, int *lsb, int *inexact,
                        int *tiny) {
    struct wide n = r->n;
    int t = top(&n);
    int l = r->exp + t - 63;
    if (l < lsb_min) l = lsb_min;
    int s = l - r->exp, round = 0, rest = r->sticky;
    if (s <= 0) {
        shift_left(&n, -s);
    } else {
        rest |= shift_right(&n, s - 1);
        round = (int)(n.w[0] & 1);
        shift_right(&n, 1);
    }
    uint64_t q = n.w[0];
    *inexact = round || rest;
    *tiny = !(q >> 63);
    int up;
    switch (mode) {
    case NEAREST: up = round && (rest || (q & 1)); break;
    case UPWARD: up = *inexact && !r->neg; break;
    case DOWNWARD: up = *inexact && r->neg; break;
    case TO_ODD: q |= (uint64_t)*inexact; up = 0; break;
    default: up = 0; break;
    }
    if (up && ++q == 0) {
        q = UINT64_C(1) << 63;
        l++;
    }
    *lsb = l;
    return q;
}

/* Boldo and Melquiond, "Emulation of FMA and correctly rounded sums: proved algorithms using rounding
 * to odd", IEEE Trans. Computers 57(4), 2008: rounded to odd at 64 bits, then to 53. */
static long double to_odd(struct operand a, struct operand b, struct operand c, int *zero) {
    struct exact r;
    int l, inexact, tiny;
    *zero = !exact_sum(a, b, c, &r);
    if (*zero) return 0;
    uint64_t q = round64(&r, -(1 << 20), TO_ODD, &l, &inexact, &tiny);
    union ld80 v;
    v.v = 0;
    v.p.m = q;
    v.p.se = (uint16_t)(r.neg << 15 | (l + 63 + 16383));
    return v.v;
}

double __recaulk_fma(double a, double b, double c) {
    if (!__builtin_isfinite(a) || !__builtin_isfinite(b) || !__builtin_isfinite(c)) {
        if (__builtin_isfinite(a) && __builtin_isfinite(b)) return c + c;
        return a * b + c;
    }
    if (a == 0 || b == 0) return a * b + c;
    if (c == 0) return a * b;
    int zero;
    long double r = to_odd(from_double(a), from_double(b), from_double(c), &zero);
    if (zero) return current_rounding() == DOWNWARD ? -0.0 : 0.0;
    return (double)r;
}

long double __recaulk_fmal(long double a, long double b, long double c) {
    if (!__builtin_isfinite(a) || !__builtin_isfinite(b) || !__builtin_isfinite(c)) {
        if (__builtin_isfinite(a) && __builtin_isfinite(b)) return c + c;
        return a * b + c;
    }
    if (a == 0 || b == 0) return a * b + c;
    if (c == 0) return a * b;
    enum rounding mode = current_rounding();
    struct exact r;
    if (!exact_sum(from_ld(a), from_ld(b), from_ld(c), &r)) return mode == DOWNWARD ? -0.0L : 0.0L;
    int l, inexact, tiny;
    uint64_t q = round64(&r, -16445, mode, &l, &inexact, &tiny);
    union ld80 v;
    v.v = 0;
    if (l > 16383 - 63) {
        feraiseexcept(FE_OVERFLOW | FE_INEXACT);
        if (mode == NEAREST || (mode == UPWARD && !r.neg) || (mode == DOWNWARD && r.neg)) {
            v.p.m = UINT64_C(1) << 63;
            v.p.se = (uint16_t)(r.neg << 15 | 0x7fff);
        } else {
            v.p.m = ~UINT64_C(0);
            v.p.se = (uint16_t)(r.neg << 15 | 0x7ffe);
        }
        return v.v;
    }
    if (inexact) feraiseexcept(tiny ? FE_UNDERFLOW | FE_INEXACT : FE_INEXACT);
    v.p.m = q;
    v.p.se = (uint16_t)(r.neg << 15 | (q >> 63 ? l + 63 + 16383 : 0));
    return v.v;
}

long double __recaulk_truncl(long double x) {
    union ld80 v;
    v.v = x;
    int e = (v.p.se & 0x7fff) - 16383;
    if (e >= 63) return x != x ? x + x : x;
    if (e < 0) return v.p.se >> 15 ? -0.0L : 0.0L;
    return (long double)(long long)x;
}

#define IMAGE_LOCAL __attribute__((weak, visibility("hidden")))
IMAGE_LOCAL double recaulk_shadow_fma(double, double, double) __asm("_fma");
double recaulk_shadow_fma(double a, double b, double c) { return __recaulk_fma(a, b, c); }
IMAGE_LOCAL long double recaulk_shadow_fmal(long double, long double, long double) __asm("_fmal");
long double recaulk_shadow_fmal(long double a, long double b, long double c) { return __recaulk_fmal(a, b, c); }
IMAGE_LOCAL long double recaulk_shadow_truncl(long double) __asm("_truncl");
long double recaulk_shadow_truncl(long double x) { return __recaulk_truncl(x); }
