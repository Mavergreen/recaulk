#include <stdarg.h>
#include <string.h>

__attribute__((aligned(256))) int mgfwd_varargs(const char *fmt, ...) {
  va_list ap;
  size_t i, n = strlen(fmt);
  int sum = 0;
  va_start(ap, fmt);
  for (i = 0; i < n; i++)
    sum += fmt[i] == 'f' ? (int)va_arg(ap, double) : va_arg(ap, int);
  va_end(ap);
  return sum + 1000;
}

__attribute__((aligned(256))) double mgfwd_float(double a, float b, int c, double d, double e,
                                                 double f, double g, double h, double i,
                                                 double j) {
  return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * h + 9 * i + 10 * j + 1000;
}

__asm__(".text\n"
        ".globl _mgfwd_nop\n"
        ".p2align 8\n"
        "_mgfwd_nop:\n"
        "  ret\n");
