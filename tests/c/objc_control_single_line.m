#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

@interface NSControl (RecaulkSingleLineTest)
- (BOOL)usesSingleLineMode;
- (void)setUsesSingleLineMode:(BOOL)flag;
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

static void encoding(SEL sel, const char *want) {
	const char *types = method_getTypeEncoding(class_getInstanceMethod([NSControl class], sel));
	CHECK(types && strcmp(types, want) == 0, "%s's encoding is %s, not %s", sel_getName(sel), types ? types : "(none)", want);
}

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL rooted = argc > 1 && strcmp(argv[1], "rooted") == 0;
	NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)] autorelease];
	BOOL getter = [field respondsToSelector:@selector(usesSingleLineMode)];
	BOOL setter = [field respondsToSelector:@selector(setUsesSingleLineMode:)];
	if (!rooted) {
		/* platform: 10.9's NSControl has no usesSingleLineMode (10.10); its NSCell has (10.6) */
		CHECK(!getter && !setter, "an unrooted program's NSControl has usesSingleLineMode");
	} else {
		CHECK(getter && setter, "a rooted program's NSControl lacks usesSingleLineMode or its setter");
		if (getter && setter) {
			NSCell *cell = [field cell];
			[field setUsesSingleLineMode:YES];
			CHECK([cell usesSingleLineMode] == YES, "setting the control's did not set its cell's");
			CHECK([field usesSingleLineMode] == YES, "the control does not read YES back");
			[cell setUsesSingleLineMode:NO];
			CHECK([field usesSingleLineMode] == NO, "the control does not read its cell's NO");
			NSControl *bare = [[[NSControl alloc] initWithFrame:NSZeroRect] autorelease];
			[bare setCell:nil];
			[bare setUsesSingleLineMode:YES];
			CHECK([bare usesSingleLineMode] == NO, "a control with no cell reads YES");
			encoding(@selector(usesSingleLineMode), "c16@0:8");
			encoding(@selector(setUsesSingleLineMode:), "v20@0:8c16");
		}
	}
	[pool drain];
	if (failures) return 1;
	printf("objc_control_single_line %s: ok\n", rooted ? "rooted" : "unrooted");
	return 0;
}
