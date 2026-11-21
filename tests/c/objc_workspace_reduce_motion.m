#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

@interface NSWorkspace (RecaulkReduceMotionTest)
- (BOOL)accessibilityDisplayShouldReduceMotion;
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL rooted = argc > 1 && strcmp(argv[1], "rooted") == 0;
	SEL sel = @selector(accessibilityDisplayShouldReduceMotion);
	BOOL responds = [[NSWorkspace sharedWorkspace] respondsToSelector:sel];
	if (!rooted) {
		/* platform: 10.9's NSWorkspace has no accessibilityDisplayShouldReduceMotion (10.12) */
		CHECK(!responds, "an unrooted program's NSWorkspace has accessibilityDisplayShouldReduceMotion");
	} else {
		CHECK(responds, "a rooted program's NSWorkspace has no accessibilityDisplayShouldReduceMotion");
		if (responds) {
			/* platform: 10.9 has no reduce-motion setting; it arrived in 10.12 */
			CHECK([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion] == NO, "reduce motion reads as on");
			const char *types = method_getTypeEncoding(class_getInstanceMethod([NSWorkspace class], sel));
			CHECK(types && strcmp(types, "c16@0:8") == 0, "the method's encoding is %s, not c16@0:8", types ? types : "(none)");
		}
	}
	[pool drain];
	if (failures) return 1;
	printf("objc_workspace_reduce_motion %s: ok\n", rooted ? "rooted" : "unrooted");
	return 0;
}
