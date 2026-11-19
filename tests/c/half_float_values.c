#include <math.h>
#include <stdint.h>
#include <stdio.h>

float __extendhfsf2(uint16_t half);
uint16_t __truncsfhf2(float value);

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

int main(void) {
	/* Every half is exact as a float, so narrowing it back gives the same half (NaNs: still a NaN). */
	for (uint32_t h = 0; h <= 0xffff; h++) {
		float f = __extendhfsf2((uint16_t)h);
		uint16_t back = __truncsfhf2(f);
		if ((h & 0x7c00) == 0x7c00 && (h & 0x3ff)) CHECK(isnan(f) && (back & 0x7c00) == 0x7c00 && (back & 0x3ff), "half 0x%04x is not a NaN both ways", h);
		else CHECK(back == h, "half 0x%04x widens to %a and narrows to 0x%04x", h, f, back);
	}
	CHECK(__extendhfsf2(0x3c00) == 1.0f, "0x3c00 is not 1");
	CHECK(__extendhfsf2(0x0001) == ldexpf(1, -24), "0x0001 is not the least subnormal");
	CHECK(__extendhfsf2(0xfc00) == -INFINITY, "0xfc00 is not -inf");
	/* Round to nearest, ties to even. */
	CHECK(__truncsfhf2(65504.0f) == 0x7bff, "65504 is not the largest half");
	CHECK(__truncsfhf2(65519.0f) == 0x7bff, "65519 rounds up past the largest half");
	CHECK(__truncsfhf2(65520.0f) == 0x7c00, "65520 does not round to inf");
	CHECK(__truncsfhf2(ldexpf(1, -25)) == 0x0000, "a tie at 2^-25 is not rounded to even 0");
	CHECK(__truncsfhf2(ldexpf(3, -25)) == 0x0002, "a tie at 3*2^-25 is not rounded to even 2");
	CHECK(__truncsfhf2(1.0f + ldexpf(1, -11)) == 0x3c00, "a tie above 1 is not rounded to even");
	CHECK(__truncsfhf2(1.0f + ldexpf(3, -11)) == 0x3c02, "a tie at 1+3*2^-11 is not rounded to even");
	CHECK(__truncsfhf2(-0.0f) == 0x8000, "-0 loses its sign");
	if (failures) return 1;
	printf("half_float_values: ok\n");
	return 0;
}
