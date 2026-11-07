double __recaulk_fma(double a, double b, double c);
long double __recaulk_fmal(long double a, long double b, long double c);
long double __recaulk_truncl(long double x);

double recaulk_export_fma(double, double, double) __asm("_fma");
double recaulk_export_fma(double a, double b, double c) { return __recaulk_fma(a, b, c); }
long double recaulk_export_fmal(long double, long double, long double) __asm("_fmal");
long double recaulk_export_fmal(long double a, long double b, long double c) { return __recaulk_fmal(a, b, c); }
long double recaulk_export_truncl(long double) __asm("_truncl");
long double recaulk_export_truncl(long double x) { return __recaulk_truncl(x); }
