#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

@interface NSWindow (RecaulkTitlebarTest)
- (BOOL)titlebarAppearsTransparent;
- (void)setTitlebarAppearsTransparent:(BOOL)flag;
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

static void encoding(SEL sel, const char *want) {
	const char *types = method_getTypeEncoding(class_getInstanceMethod([NSWindow class], sel));
	CHECK(types && strcmp(types, want) == 0, "%s's encoding is %s, not %s", sel_getName(sel), types ? types : "(none)", want);
}

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL rooted = argc > 1 && strcmp(argv[1], "rooted") == 0;
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
	                                               styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:YES];
	BOOL getter = [window respondsToSelector:@selector(titlebarAppearsTransparent)];
	BOOL setter = [window respondsToSelector:@selector(setTitlebarAppearsTransparent:)];
	if (!rooted) {
		/* platform: 10.9's NSWindow has no titlebarAppearsTransparent (10.10) */
		CHECK(!getter && !setter, "an unrooted program's NSWindow has titlebarAppearsTransparent");
	} else {
		CHECK(getter && setter, "a rooted program's NSWindow lacks titlebarAppearsTransparent or its setter");
		if (getter && setter) {
			CHECK([window titlebarAppearsTransparent] == NO, "a new window's titlebar reads transparent");
			[window setTitlebarAppearsTransparent:NO];
			CHECK([window titlebarAppearsTransparent] == NO, "setting NO did not read NO back");
			/* 10.9 draws no transparent titlebar: YES is accepted and ignored, as the window looks */
			[window setTitlebarAppearsTransparent:YES];
			CHECK([window titlebarAppearsTransparent] == NO, "setting YES read YES, which 10.9 cannot draw");
			encoding(@selector(titlebarAppearsTransparent), "c16@0:8");
			encoding(@selector(setTitlebarAppearsTransparent:), "v20@0:8c16");
		}
	}
	[window release];
	[pool drain];
	if (failures) return 1;
	printf("objc_window_titlebar %s: ok\n", rooted ? "rooted" : "unrooted");
	return 0;
}
