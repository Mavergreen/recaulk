#include <fenv.h>
#include <stdint.h>

#include "libm_exact.h"

#pragma STDC FENV_ACCESS ON

typedef unsigned __int128 u128;

enum recaulk_rounding __recaulk_libm_rounding(void) {
    switch (fegetround()) {
    case FE_TOWARDZERO: return RECAULK_TOWARD_ZERO;
    case FE_UPWARD: return RECAULK_UPWARD;
    case FE_DOWNWARD: return RECAULK_DOWNWARD;
    default: return RECAULK_NEAREST;
    }
}

struct recaulk_operand __recaulk_libm_from_double(double x) {
    union {
        double d;
        uint64_t u;
    } v = {x};
    struct recaulk_operand o;
    int e = (int)(v.u >> 52 & 0x7ff);
    o.neg = (int)(v.u >> 63);
    o.m = v.u & ((UINT64_C(1) << 52) - 1);
    if (e) o.m |= UINT64_C(1) << 52;
    o.exp = (e ? e : 1) - 1075;
    return o;
}

struct recaulk_operand __recaulk_libm_from_ld(long double x) {
    union recaulk_ld80 v;
    struct recaulk_operand o;
    v.v = x;
    int e = v.p.se & 0x7fff;
    o.neg = v.p.se >> 15;
    o.m = v.p.m;
    o.exp = (e ? e : 1) - 16383 - 63;
    return o;
}

static int top(const uint64_t *n) {
    for (int i = 2; i >= 0; i--)
        if (n[i]) return 64 * i + 63 - __builtin_clzll(n[i]);
    return -1;
}

static void shift_left(uint64_t *n, int s) {
    while (s >= 64) {
        n[2] = n[1];
        n[1] = n[0];
        n[0] = 0;
        s -= 64;
    }
    if (s) {
        n[2] = n[2] << s | n[1] >> (64 - s);
        n[1] = n[1] << s | n[0] >> (64 - s);
        n[0] <<= s;
    }
}

static int shift_right(uint64_t *n, int s) {
    int lost = 0;
    if (s >= 192) {
        lost = n[0] || n[1] || n[2];
        n[0] = n[1] = n[2] = 0;
        return lost;
    }
    while (s >= 64) {
        lost |= n[0] != 0;
        n[0] = n[1];
        n[1] = n[2];
        n[2] = 0;
        s -= 64;
    }
    if (s) {
        lost |= (n[0] << (64 - s)) != 0;
        n[0] = n[0] >> s | n[1] << (64 - s);
        n[1] = n[1] >> s | n[2] << (64 - s);
        n[2] >>= s;
    }
    return lost;
}

static int less(const uint64_t *x, const uint64_t *y) {
    for (int i = 2; i >= 0; i--)
        if (x[i] != y[i]) return x[i] < y[i];
    return 0;
}

static void add(uint64_t *x, const uint64_t *y) {
    uint64_t carry = 0;
    for (int i = 0; i < 3; i++) {
        u128 s = (u128)x[i] + y[i] + carry;
        x[i] = (uint64_t)s;
        carry = (uint64_t)(s >> 64);
    }
}

static void subtract(uint64_t *x, const uint64_t *y, int extra) {
    uint64_t borrow = (uint64_t)extra;
    for (int i = 0; i < 3; i++) {
        u128 d = (u128)x[i] - y[i] - borrow;
        x[i] = (uint64_t)d;
        borrow = (uint64_t)(d >> 64) & 1;
    }
}

static void swap(uint64_t *x, uint64_t *y) {
    for (int i = 0; i < 3; i++) {
        uint64_t t = x[i];
        x[i] = y[i];
        y[i] = t;
    }
}

int __recaulk_libm_exact_sum(struct recaulk_operand a, struct recaulk_operand b, struct recaulk_operand c,
                             struct recaulk_exact *r) {
    u128 p = (u128)a.m * b.m;
    uint64_t x[3] = {(uint64_t)p, (uint64_t)(p >> 64), 0}, y[3] = {c.m, 0, 0};
    int xneg = a.neg ^ b.neg, yneg = c.neg;
    int tx = top(x), ty = top(y);
    int topx = a.exp + b.exp + tx, topy = c.exp + ty;
    if (topy > topx) {
        swap(x, y);
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
    shift_left(x, 189 - tx);
    int s = 189 - (topx - topy) - ty, sticky = 0;
    if (s >= 0)
        shift_left(y, s);
    else
        sticky = shift_right(y, -s);
    if (xneg == yneg) {
        add(x, y);
    } else {
        if (less(x, y)) {
            swap(x, y);
            xneg = yneg;
        }
        subtract(x, y, sticky);
    }
    if (!sticky && !x[0] && !x[1] && !x[2]) return 0;
    r->neg = xneg;
    r->exp = topx - 189;
    r->sticky = sticky;
    for (int i = 0; i < 3; i++) r->n[i] = x[i];
    return 1;
}

uint64_t __recaulk_libm_round64(const struct recaulk_exact *r, int lsb_min, enum recaulk_rounding mode, int *lsb,
                                int *inexact) {
    uint64_t n[3] = {r->n[0], r->n[1], r->n[2]};
    int l = r->exp + top(n) - 63;
    if (l < lsb_min) l = lsb_min;
    int s = l - r->exp, round = 0, rest = r->sticky;
    if (s <= 0) {
        shift_left(n, -s);
    } else {
        rest |= shift_right(n, s - 1);
        round = (int)(n[0] & 1);
        shift_right(n, 1);
    }
    uint64_t q = n[0];
    int up;
    *inexact = round || rest;
    switch (mode) {
    case RECAULK_NEAREST: up = round && (rest || (q & 1)); break;
    case RECAULK_UPWARD: up = *inexact && !r->neg; break;
    case RECAULK_DOWNWARD: up = *inexact && r->neg; break;
    case RECAULK_TO_ODD: q |= (uint64_t)*inexact; up = 0; break;
    default: up = 0; break;
    }
    if (up && ++q == 0) {
        q = UINT64_C(1) << 63;
        l++;
    }
    *lsb = l;
    return q;
}
