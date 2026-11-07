#include <stdint.h>

enum recaulk_rounding { RECAULK_NEAREST, RECAULK_TOWARD_ZERO, RECAULK_UPWARD, RECAULK_DOWNWARD, RECAULK_TO_ODD };

struct recaulk_operand {
    int neg, exp;
    uint64_t m;
};

struct recaulk_exact {
    int neg, exp, sticky;
    uint64_t n[3];
};

union recaulk_ld80 {
    long double v;
    struct {
        uint64_t m;
        uint16_t se;
    } p;
};

enum recaulk_rounding __recaulk_libm_rounding(void);
struct recaulk_operand __recaulk_libm_from_double(double x);
struct recaulk_operand __recaulk_libm_from_ld(long double x);
int __recaulk_libm_exact_sum(struct recaulk_operand a, struct recaulk_operand b, struct recaulk_operand c,
                             struct recaulk_exact *r);
uint64_t __recaulk_libm_round64(const struct recaulk_exact *r, int lsb_min, enum recaulk_rounding mode, int *lsb,
                                int *inexact);
