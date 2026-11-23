#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

@interface NSTableColumn (RecaulkTitleTest)
- (NSString *)title;
- (void)setTitle:(NSString *)title;
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

static void encoding(SEL sel, const char *want) {
	const char *types = method_getTypeEncoding(class_getInstanceMethod([NSTableColumn class], sel));
	CHECK(types && strcmp(types, want) == 0, "%s's encoding is %s, not %s", sel_getName(sel), types ? types : "(none)", want);
}

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL rooted = argc > 1 && strcmp(argv[1], "rooted") == 0;
	NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"c"] autorelease];
	BOOL getter = [column respondsToSelector:@selector(title)];
	BOOL setter = [column respondsToSelector:@selector(setTitle:)];
	if (!rooted) {
		/* platform: 10.9's NSTableColumn has no title (10.10); its header cell's stringValue is the title */
		CHECK(!getter && !setter, "an unrooted program's NSTableColumn has title");
	} else {
		CHECK(getter && setter, "a rooted program's NSTableColumn lacks title or setTitle:");
		if (getter && setter) {
			NSCell *header = [column headerCell];
			[column setTitle:@"Name"];
			CHECK([[header stringValue] isEqualToString:@"Name"], "setTitle: did not set the header cell's string");
			[header setStringValue:@"Guid"];
			CHECK([[column title] isEqualToString:@"Guid"], "title is not the header cell's string");
			NSMutableString *m = [NSMutableString stringWithString:@"Copy"];
			[column setTitle:m];
			[m appendString:@"!"];
			CHECK([[column title] isEqualToString:@"Copy"], "title did not copy a mutable string");
			[column setTitle:nil];
			CHECK([[column title] isEqualToString:@""], "a nil title does not read back as the empty string");
			encoding(@selector(title), "@16@0:8");
			encoding(@selector(setTitle:), "v24@0:8@16");
		}
	}
	[pool drain];
	if (failures) return 1;
	printf("objc_tablecolumn_title %s: ok\n", rooted ? "rooted" : "unrooted");
	return 0;
}
