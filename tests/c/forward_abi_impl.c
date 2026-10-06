#include <stdarg.h>
#include <string.h>

/* platform: a variadic call passes in al the number of vector registers it used, and the callee
   saves xmm0-7 only when al is non-zero; a 256-byte-aligned entry point leaves al zero if a
   trampoline lets the resolved address overwrite it */
__attribute__((aligned(256))) int mgfwd_varargs(const char *fmt, ...) {
  va_list ap;
  size_t i, n = strlen(fmt);
  int sum = 0;
  va_start(ap, fmt);
  for (i = 0; i < n; i++)
    sum += fmt[i] == 'f' ? (int)va_arg(ap, double) : va_arg(ap, int);
  va_end(ap);
  return sum;
}

__attribute__((aligned(256))) double mgfwd_float(double a, float b, int c, double d, double e,
                                                 double f, double g, double h, double i,
                                                 double j) {
  return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * h + 9 * i + 10 * j;
}

/* platform: a function that touches no register, so whatever a caller keeps in r10, r11 or
   xmm8-15 survives the call unless the trampoline in front of it loses it */
__asm__(".text\n"
        ".globl _mgfwd_nop\n"
        ".p2align 8\n"
        "_mgfwd_nop:\n"
        "  ret\n");
