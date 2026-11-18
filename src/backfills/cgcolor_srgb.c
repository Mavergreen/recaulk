#include <CoreGraphics/CoreGraphics.h>

/* CGColorCreateSRGB (added 10.15): a color in the named sRGB space, which 10.9 already has. */
CGColorRef CGColorCreateSRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
	const CGFloat components[4] = {red, green, blue, alpha};
	CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGColorRef color;
	if (!space) return NULL;
	color = CGColorCreate(space, components);
	CGColorSpaceRelease(space);
	return color;
}
