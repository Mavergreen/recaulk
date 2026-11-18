#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/utsname.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

static int is_named_srgb(CGColorRef color) {
	CGColorSpaceRef expected = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	int same = expected && CFEqual(CGColorGetColorSpace(color), expected);
	if (expected) CGColorSpaceRelease(expected);
	return same;
}

/* platform: CGColorCreateSRGB is Apple's own from 10.15 (Darwin 19); below that, Recaulk's answers. */
static int recaulk_backfill(void) {
	struct utsname u;
	return uname(&u) == 0 && atoi(u.release) < 19;
}

static CGFloat clamp01(CGFloat v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

/* The named sRGB space is not extended-range, so CGColorCreate keeps each component within 0...1. */
static void check(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
	const CGFloat want[4] = {clamp01(r), clamp01(g), clamp01(b), clamp01(a)};
	CGColorRef color = CGColorCreateSRGB(r, g, b, a);
	CHECK(color != NULL, "CGColorCreateSRGB(%g, %g, %g, %g) is NULL", r, g, b, a);
	if (!color) return;
	CHECK(is_named_srgb(color), "(%g, %g, %g, %g) is not in the named sRGB space", r, g, b, a);
	CHECK(CGColorGetNumberOfComponents(color) == 4, "(%g, %g, %g, %g) has %zu components, want 4",
	      r, g, b, a, CGColorGetNumberOfComponents(color));
	const CGFloat *got = CGColorGetComponents(color);
	for (int i = 0; i < 4; i++)
		CHECK(fabs(got[i] - want[i]) < 1e-12, "(%g, %g, %g, %g) component %d is %g", r, g, b, a, i, got[i]);
	CHECK(fabs(CGColorGetAlpha(color) - want[3]) < 1e-12, "(%g, %g, %g, %g) alpha is %g", r, g, b, a, CGColorGetAlpha(color));
	/* platform: newer CoreGraphics may hand back a shared constant color, so only Recaulk's own is held to 1. */
	if (recaulk_backfill())
		CHECK(CFGetRetainCount(color) == 1, "(%g, %g, %g, %g) retain count is %ld, want 1 (a Create)",
		      r, g, b, a, (long)CFGetRetainCount(color));
	CGColorRelease(color);
}

int main(void) {
	check(0, 0, 0, 0);
	check(1, 1, 1, 1);
	check(0.125, 0.375, 0.625, 0.875);
	check(1.5, -0.25, 0.5, 1);
	/* The space check must tell sRGB from device RGB, or it proves nothing. */
	CGColorSpaceRef device = CGColorSpaceCreateDeviceRGB();
	const CGFloat c[4] = {0.5, 0.5, 0.5, 1};
	CGColorRef wrong = CGColorCreate(device, c);
	CHECK(!is_named_srgb(wrong), "a device RGB color passes as named sRGB: the space check is vacuous");
	CGColorRelease(wrong);
	CGColorSpaceRelease(device);
	if (failures) return 1;
	printf("cgcolor_srgb: ok\n");
	return 0;
}
