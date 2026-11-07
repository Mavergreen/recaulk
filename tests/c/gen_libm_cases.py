#!/usr/bin/env python
# platform: host-agnostic -- Python 2.7 (10.9's) or 3; exact rational arithmetic, no libm
from __future__ import print_function
import sys
from fractions import Fraction

MODES = ("nearest", "zero", "up", "down")


class Fmt(object):
    def __init__(self, name, p, emin, emax, ebits, explicit):
        self.name, self.p, self.emin, self.emax = name, p, emin, emax
        self.ebits, self.explicit = ebits, explicit
        self.bias = (1 << (ebits - 1)) - 1
        self.lsb_min = emin - (p - 1)
        self.fbits = p if explicit else p - 1


F32 = Fmt("float", 24, -126, 127, 8, False)
F64 = Fmt("double", 53, -1022, 1023, 11, False)
F80 = Fmt("long double", 64, -16382, 16383, 15, True)


def encode(f, neg, n, lsb):
    if n == 0:
        be, frac = 0, 0
    elif n < (1 << (f.p - 1)):
        assert lsb == f.lsb_min
        be, frac = 0, n
    else:
        be = lsb + f.p - 1 + f.bias
        frac = n if f.explicit else n - (1 << (f.p - 1))
    return (int(neg) << (f.ebits + f.fbits)) | (be << f.fbits) | frac


def inf_bits(f, neg):
    top = (1 << (f.p - 1)) if f.explicit else 0
    return (int(neg) << (f.ebits + f.fbits)) | (((1 << f.ebits) - 1) << f.fbits) | top


def max_bits(f, neg):
    return encode(f, neg, (1 << f.p) - 1, f.emax - (f.p - 1))


def decode(f, bits):
    neg = (bits >> (f.ebits + f.fbits)) & 1
    be = (bits >> f.fbits) & ((1 << f.ebits) - 1)
    frac = bits & ((1 << f.fbits) - 1)
    assert be != (1 << f.ebits) - 1
    if be == 0:
        n, lsb = frac, f.lsb_min
    else:
        n = frac if f.explicit else frac | (1 << (f.p - 1))
        lsb = be - f.bias - (f.p - 1)
    v = Fraction(n) * (Fraction(2) ** lsb)
    return -v if neg else v


def floor_log2(x):
    e = x.numerator.bit_length() - x.denominator.bit_length()
    if Fraction(2) ** e > x:
        e -= 1
    return e


def round_to(f, x, mode, zero_neg):
    if x == 0:
        return encode(f, zero_neg, 0, 0)
    neg = x < 0
    ax = -x if neg else x
    lsb = max(floor_log2(ax), f.emin) - (f.p - 1)
    q = ax / (Fraction(2) ** lsb)
    n = q.numerator // q.denominator
    r = q - n
    if mode == "nearest":
        up = r > Fraction(1, 2) or (r == Fraction(1, 2) and n & 1)
    elif mode == "zero":
        up = False
    elif mode == "up":
        up = r > 0 and not neg
    else:
        up = r > 0 and neg
    if up:
        n += 1
        if n == 1 << f.p:
            n >>= 1
            lsb += 1
    if lsb + f.p - 1 > f.emax:
        to_inf = mode == "nearest" or (mode == "up" and not neg) or (mode == "down" and neg)
        return inf_bits(f, neg) if to_inf else max_bits(f, neg)
    return encode(f, neg, n, lsb)


def signbit(f, bits):
    return (bits >> (f.ebits + f.fbits)) & 1


def fma_all(f, a, b, c):
    va, vb, vc = decode(f, a), decode(f, b), decode(f, c)
    x = va * vb + vc
    out = []
    for m in MODES:
        if x == 0:
            pneg = signbit(f, a) ^ signbit(f, b)
            if (va * vb == 0) and (vc == 0) and pneg == signbit(f, c):
                zneg = pneg
            else:
                zneg = m == "down"
        else:
            zneg = False
        out.append(round_to(f, x, m, zneg))
    return out


class Rng(object):
    def __init__(self, seed):
        self.s = seed

    def next(self):
        s = self.s
        s ^= (s << 13) & 0xFFFFFFFFFFFFFFFF
        s ^= s >> 7
        s ^= (s << 17) & 0xFFFFFFFFFFFFFFFF
        self.s = s
        return s

    def below(self, n):
        return self.next() % n

    def bits(self, k):
        v = 0
        while k > 0:
            v = (v << 64) | self.next()
            k -= 64
        return v


def make(f, neg, n, lsb):
    if n == 0:
        return None
    while lsb < f.lsb_min:
        if n & 1:
            return None
        n >>= 1
        lsb += 1
    while n >= (1 << f.p):
        if n & 1:
            return None
        n >>= 1
        lsb += 1
    while n < (1 << (f.p - 1)) and lsb > f.lsb_min:
        n <<= 1
        lsb -= 1
    if lsb + f.p - 1 > f.emax:
        return None
    return encode(f, neg, n, lsb)


def val_bits(f, v):
    if v == 0:
        return None
    neg = v < 0
    av = -v if neg else v
    lsb = floor_log2(av) - (f.p - 1)
    q = av / (Fraction(2) ** lsb)
    if q.denominator != 1:
        return None
    return make(f, neg, q.numerator, lsb)


def rand_val(f, rng, elo, ehi):
    n = rng.bits(f.p) & ((1 << f.p) - 1) | (1 << (f.p - 1))
    e = elo + rng.below(ehi - elo + 1)
    return make(f, rng.below(2) == 1, n, e - (f.p - 1))


def hand_cases(f):
    one = Fraction(1)
    u = Fraction(2) ** (1 - f.p)
    h = Fraction(2) ** -f.p
    tiny = Fraction(2) ** f.lsb_min
    big = Fraction(2) ** f.emax
    vmax = (2 - u) * big
    cs = [
        (one + u, u - one, one),
        (one + u, one - u, -one),
        (one - u / 2, one + u, -one),
        (h * (one + u), one - u, one + u),
        (h * (one + u), -(one - u), -(one + u)),
        (h * (one - u), one + u, one),
        (one + u, one + u, -(one + 2 * u)),
        (one + 3 * u, one + 5 * u, -one),
        (vmax, one + u, -vmax),
        (vmax, one + u, -tiny),
        (vmax, 2 * one, -vmax),
        (vmax, one, vmax * u / 2),
        (big, 2 * one, -vmax),
        (Fraction(2) ** (f.emax // 2 + 1), Fraction(2) ** (f.emax // 2 + 1), -vmax),
        (Fraction(2) ** (f.emax // 2 + 1), Fraction(2) ** (f.emax - f.emax // 2), -vmax),
        (tiny, one / 2, tiny),
        (tiny, one / 2, -tiny),
        (tiny, -one / 2, 2 * tiny),
        (tiny * 3, one / 2, tiny),
        (Fraction(2) ** (f.lsb_min // 2), Fraction(2) ** (f.lsb_min // 2 - 3), tiny),
        (Fraction(2) ** (f.lsb_min // 2), -Fraction(2) ** (f.lsb_min // 2 - 3), tiny),
        (Fraction(2) ** (f.lsb_min // 2), Fraction(2) ** (f.lsb_min // 2 - 3), -tiny),
        (Fraction(2) ** (f.emin // 2), Fraction(2) ** (f.emin - f.emin // 2), -(Fraction(2) ** f.emin)),
        (Fraction(2) ** (f.emin // 2) * (one + u), Fraction(2) ** (f.emin - f.emin // 2), -(Fraction(2) ** f.emin)),
        (Fraction(2) ** f.emin * (one + u), one - u, -(Fraction(2) ** f.emin)),
        (Fraction(2) ** f.emin * (one + u), one / 2, tiny),
        (2 * one, 3 * one, -6 * one),
        (-2 * one, 3 * one, 6 * one),
        (one, one, -one + u / 2),
        (one + u, one + u, -one),
        (3 * one, one + u, -3 * one),
    ]
    out = []
    for a, b, c in cs:
        ba, bb, bc = val_bits(f, a), val_bits(f, b), val_bits(f, c)
        if ba is not None and bb is not None and bc is not None:
            out.append((ba, bb, bc))
    return out


def random_cases(f, rng, count):
    out = []
    span = f.emax - f.emin
    while len(out) < count:
        kind = rng.below(8)
        if kind <= 1:
            a = rand_val(f, rng, -40, 40)
            b = rand_val(f, rng, -40, 40)
            p = decode(f, a) * decode(f, b)
            near = round_to(f, -p, MODES[rng.below(4)], False)
            c = near
            if kind == 1:
                v = decode(f, near)
                if v != 0:
                    ulp = Fraction(2) ** (floor_log2(abs(v)) - (f.p - 1))
                    c = val_bits(f, v + ulp * (rng.below(9) - 4))
        elif kind == 2:
            a = rand_val(f, rng, -20, 20)
            b = rand_val(f, rng, -20, 20)
            d = rng.below(3 * f.p + 10)
            c = rand_val(f, rng, -d - 40, -d + 40) if rng.below(2) else rand_val(f, rng, d - 40, d + 40)
        elif kind == 3:
            a = rand_val(f, rng, f.emax // 2 - 4, f.emax // 2 + 2)
            b = rand_val(f, rng, f.emax - f.emax // 2 - 4, f.emax - f.emax // 2 + 2)
            c = rand_val(f, rng, f.emax - 3, f.emax)
        elif kind == 4:
            a = rand_val(f, rng, f.emin // 2 - f.p, f.emin // 2 + 2)
            b = rand_val(f, rng, f.emin - f.emin // 2 - f.p, f.emin - f.emin // 2 + 2)
            c = rand_val(f, rng, f.emin - f.p, f.emin + 2)
        elif kind == 5:
            n = rng.bits(f.p) & ((1 << (f.p - 1)) - 1)
            a = make(f, rng.below(2) == 1, n | 1, f.lsb_min)
            b = rand_val(f, rng, -2, 2 * f.p)
            c = rand_val(f, rng, f.emin - 2, f.emin + f.p)
        elif kind == 6:
            a = rand_val(f, rng, f.emin + 1, f.emax - 1)
            b = rand_val(f, rng, -span // 2, span // 2)
            c = rand_val(f, rng, f.emin + 1, f.emax - 1)
        else:
            k = 1 + rng.below(f.p - 2)
            a = make(f, rng.below(2) == 1, (1 << (f.p - 1)) + (rng.bits(k) & ((1 << k) - 1)), -(f.p - 1))
            b = make(f, rng.below(2) == 1, (1 << (f.p - 1)) - (rng.bits(f.p - 1 - k) & ((1 << (f.p - 1 - k)) - 1)), -(f.p - 1) - rng.below(f.p))
            c = rand_val(f, rng, -2, 2)
        if a is None or b is None or c is None:
            continue
        if decode(f, a) == 0 or decode(f, b) == 0:
            continue
        out.append((a, b, c))
    return out


def emit(f, tag, cases, width):
    print("static const struct %s_case %s_cases[] = {" % (tag, tag))
    for a, b, c in cases:
        r = fma_all(f, a, b, c)
        print("    {%s, {%s}}," % (", ".join(fmt_bits(x, width) for x in [a, b, c]), ", ".join(fmt_bits(x, width) for x in r)))
    print("};")


def fmt_bits(x, width):
    if width == 80:
        return "{0x%016xULL, 0x%04x}" % (x & 0xFFFFFFFFFFFFFFFF, x >> 64)
    return "0x%0*xU%s" % (width // 4, x, "LL" if width == 64 else "")


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    print("/* Generated by tests/c/gen_libm_cases.py %d: a, b, c, then a*b+c rounded once in" % count)
    print(" * FE_TONEAREST, FE_TOWARDZERO, FE_UPWARD and FE_DOWNWARD, from exact rational arithmetic. */")
    print("struct ld_bits { unsigned long long m; unsigned short se; };")
    print("struct f32_case { unsigned a, b, c, r[4]; };")
    print("struct f64_case { unsigned long long a, b, c, r[4]; };")
    print("struct f80_case { struct ld_bits a, b, c, r[4]; };")
    for f, tag, width, seed in ((F32, "f32", 32, 0x9E3779B97F4A7C15),
                                (F64, "f64", 64, 0xD1B54A32D192ED03),
                                (F80, "f80", 80, 0x8CB92BA72F3D8DD7)):
        cases = hand_cases(f) + random_cases(f, Rng(seed), count)
        emit(f, tag, cases, width)


main()
