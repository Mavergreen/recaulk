#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

/* AppKit's declarations are Objective-C; a C caller names the same objects as CFStringRefs. */
extern const CFStringRef NSAppearanceNameVibrantDark, NSAppearanceNameVibrantLight, NSAppearanceNameDarkAqua,
    NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua,
    NSAppearanceNameAccessibilityHighContrastVibrantLight, NSAppearanceNameAccessibilityHighContrastVibrantDark;
/* Foundation's NSEdgeInsets (AppKit's on 10.9), field for field. */
extern const struct { CGFloat top, left, bottom, right; } NSEdgeInsetsZero;

static int failures;
static void name(const char *label, CFStringRef got) {
	CFStringRef want = CFStringCreateWithCString(NULL, label, kCFStringEncodingUTF8);
	if (!got || !CFEqual(got, want)) { printf("FAIL: %s is not \"%s\"\n", label, label); failures++; }
	CFRelease(want);
}
#define NAME(n) name(#n, n)

int main(void) {
	NAME(NSAppearanceNameVibrantDark);
	NAME(NSAppearanceNameVibrantLight);
	NAME(NSAppearanceNameDarkAqua);
	NAME(NSAppearanceNameAccessibilityHighContrastAqua);
	NAME(NSAppearanceNameAccessibilityHighContrastDarkAqua);
	NAME(NSAppearanceNameAccessibilityHighContrastVibrantLight);
	NAME(NSAppearanceNameAccessibilityHighContrastVibrantDark);
	if (NSEdgeInsetsZero.top != 0 || NSEdgeInsetsZero.left != 0 || NSEdgeInsetsZero.bottom != 0 || NSEdgeInsetsZero.right != 0) {
		printf("FAIL: NSEdgeInsetsZero is not all zero\n"); failures++;
	}
	if (failures) return 1;
	printf("appkit_data: ok\n");
	return 0;
}
