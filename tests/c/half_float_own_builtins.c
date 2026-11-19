#include <stdint.h>
#include <stdio.h>

/* The program's own compiler-rt, as Zig's compiler_rt.c.o brings it: strong definitions with markers. */
float __extendhfsf2(uint16_t half) { (void)half; return 42.0f; }
uint16_t __truncsfhf2(float value) { (void)value; return 0x4242; }

int main(void) {
	volatile uint16_t h = 0x3c00; /* 1.0 */
	volatile float f = 1.0f;
	int ok = __extendhfsf2(h) == 42.0f && __truncsfhf2(f) == 0x4242;
	printf(ok ? "half_float_own_builtins: ok\n" : "FAIL: Recaulk's half-float conversion replaced the program's own\n");
	return ok ? 0 : 1;
}
