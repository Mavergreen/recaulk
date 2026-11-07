/* spec: README.md "Fixes to functions 10.9 has" -- declared before 10.9's own declaration, so a program built
   from source calls Recaulk's fix whatever its link order (a -lm or -lc ahead of librecaulk.a names libSystem,
   whose copy would otherwise bind first). Not inside Recaulk, whose own sources define the 10.9 names. */
#ifndef RECAULK_NAMES_MATH_H
#define RECAULK_NAMES_MATH_H
#ifndef __RECAULK_SOURCE__
#ifdef __cplusplus
extern "C" {
#endif
double fma(double, double, double) __asm("___recaulk_fma");
long double fmal(long double, long double, long double) __asm("___recaulk_fmal");
long double truncl(long double) __asm("___recaulk_truncl");
#ifdef __cplusplus
}
#endif
#endif
#endif
