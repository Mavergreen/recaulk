#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

/* The 10.10 NSAccessibility properties librecaulk-objc.a's NSView and NSCell groups provide, declared here as the
   10.10 SDK declares them, so this compiles against the 10.9 SDK whatever recipe a profile applies. */
#define RECAULK_AX_DECLS \
	- (void)setAccessibilityLabel:(NSString *)label; - (NSString *)accessibilityLabel; \
	- (void)setAccessibilityRole:(NSString *)role; - (NSString *)accessibilityRole; \
	- (void)setAccessibilityChildren:(NSArray *)children; - (NSArray *)accessibilityChildren; \
	- (void)setAccessibilitySelectedTextRange:(NSRange)range; - (NSRange)accessibilitySelectedTextRange; \
	- (NSRect)accessibilityFrame;
@interface NSView (RecaulkAccessibilityProvidersTest)
RECAULK_AX_DECLS
@end
@interface NSCell (RecaulkAccessibilityProvidersTest)
RECAULK_AX_DECLS
@end
@interface NSObject (RecaulkAccessibilityProvidersTest)
- (NSDictionary *)accessibilityOverriddenAttributes; /* platform: 10.9 AppKit, NSObject(NSAccessibilityOverriddenAttributes) */
@end
#ifdef RECAULK_OWN_VIEW_LABEL
/* A program's own -[NSView accessibilityLabel]: the NSView group finds a member already there, so it adds none of its
   members; the NSCell group is independent and still adds its own. */
@implementation NSView (RecaulkOwnViewLabel)
- (NSString *)accessibilityLabel { return @"own"; }
@end
#endif

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

static const char *sels[] = {"setAccessibilityLabel:", "accessibilityLabel", "setAccessibilityRole:", "accessibilityRole",
	"setAccessibilityChildren:", "accessibilityChildren", "setAccessibilitySelectedTextRange:",
	"accessibilitySelectedTextRange", "accessibilityFrame"};
static const char *encodings[] = {"v24@0:8@16", "@16@0:8", "v24@0:8@16", "@16@0:8", "v24@0:8@16", "@16@0:8",
	"v32@0:8{_NSRange=QQ}16", "{_NSRange=QQ}16@0:8", "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8"};
#define NSELS (sizeof sels / sizeof *sels)

static int members(Class c) {
	int n = 0;
	for (unsigned i = 0; i < NSELS; i++) n += class_getInstanceMethod(c, sel_registerName(sels[i])) != NULL;
	return n;
}
static void encoded(Class c) {
	for (unsigned i = 0; i < NSELS; i++) {
		Method m = class_getInstanceMethod(c, sel_registerName(sels[i]));
		const char *t = m ? method_getTypeEncoding(m) : NULL;
		CHECK(t && strcmp(t, encodings[i]) == 0, "-[%s %s]'s encoding is %s, not %s", class_getName(c), sels[i],
		      t ? t : "(none)", encodings[i]);
	}
}
static BOOL same(id a, id b) { return a == b || [a isEqual:b]; }
static id overridden(id e, NSString *attr) { return [[e accessibilityOverriddenAttributes] objectForKey:attr]; }

/* What both groups share: a value set reads back, nil clears it, and an attribute 10.9 has reads through. */
static void element(id e, const char *what, NSString *nativeRole) {
	CHECK(same([e accessibilityRole], nativeRole), "%s's unset role is %s, not %s", what, [[[e accessibilityRole] description] UTF8String],
	      [nativeRole UTF8String]);
	[e setAccessibilityRole:@"AXButton"];
	CHECK(same([e accessibilityRole], @"AXButton"), "%s's role does not read back as set", what);
	[e setAccessibilityRole:nil];
	CHECK(same([e accessibilityRole], nativeRole), "%s's role is not 10.9's again once set to nil", what);
	[e setAccessibilityLabel:@"Label"];
	CHECK(same([e accessibilityLabel], @"Label"), "%s's label reads back as %s", what, [[[e accessibilityLabel] description] UTF8String]);
	[e setAccessibilityLabel:nil];
	CHECK([e accessibilityLabel] == nil, "%s's label is %s once set to nil", what, [[[e accessibilityLabel] description] UTF8String]);
	NSArray *kids = [NSArray arrayWithObject:[[[NSView alloc] init] autorelease]];
	[e setAccessibilityChildren:kids];
	CHECK(same([e accessibilityChildren], kids), "%s's children do not read back as set", what);
	[e setAccessibilityChildren:nil];
	[e setAccessibilitySelectedTextRange:NSMakeRange(2, 3)];
	NSRange r = [e accessibilitySelectedTextRange];
	CHECK(r.location == 2 && r.length == 3, "%s's selected range reads back as {%lu, %lu}", what, (unsigned long)r.location,
	      (unsigned long)r.length);
	[e setAccessibilitySelectedTextRange:NSMakeRange(NSNotFound, 0)];
}

static void views(void) {
	NSView *v = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
	element(v, "a plain NSView", NSAccessibilityUnknownRole);
	[v setAccessibilityLabel:@"Here"];
	CHECK(same(overridden(v, NSAccessibilityDescriptionAttribute), @"Here"),
	      "a plain NSView's label is not its AXDescription override");
	NSRange none = [v accessibilitySelectedTextRange];
	CHECK(none.location == NSNotFound && none.length == 0, "an NSView with no text range reads {%lu, %lu}, not {NSNotFound, 0}",
	      (unsigned long)none.location, (unsigned long)none.length);
	CHECK([v accessibilityChildren] != nil && [[v accessibilityChildren] count] == 0, "a childless NSView's children are not empty");

	/* platform: 10.9 AppKit -- a control is ignored and its cell is the element (accessibilityIsIgnored), and an
	   ignored element's overrides are dropped (accessibilityAllowsOverriddenAttributesWhenIgnored is NO), so the
	   control's setters write to its cell, as 10.10's NSControl forwards to its cell */
	NSPopUpButton *pop = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 50, 20) pullsDown:NO] autorelease];
	@try {
		[pop setAccessibilityLabel:@"Profiles"];
	} @catch (NSException *x) {
		CHECK(0, "-[NSPopUpButton setAccessibilityLabel:] threw %s", [[x reason] UTF8String]);
	}
	CHECK(same(overridden([pop cell], NSAccessibilityDescriptionAttribute), @"Profiles"),
	      "an NSPopUpButton's label is not on its cell, the element 10.9 exposes");
	CHECK(same([pop accessibilityLabel], @"Profiles") && same([[pop cell] accessibilityLabel], @"Profiles"),
	      "an NSPopUpButton's label does not read back from the button and its cell");
	CHECK(same([pop accessibilityRole], NSAccessibilityPopUpButtonRole), "an NSPopUpButton's role is %s, not its cell's",
	      [[[pop accessibilityRole] description] UTF8String]);

	NSTextView *t = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
	[t setString:@"hello"];
	[t setSelectedRange:NSMakeRange(1, 2)];
	NSRange s = [t accessibilitySelectedTextRange];
	CHECK(s.location == 1 && s.length == 2, "an NSTextView's selected range reads {%lu, %lu}, not its selection {1, 2}",
	      (unsigned long)s.location, (unsigned long)s.length);

	NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 200, 300, 200) styleMask:NSBorderlessWindowMask
	                                            backing:NSBackingStoreBuffered defer:YES];
	NSView *in = [[[NSView alloc] initWithFrame:NSMakeRect(10, 20, 30, 40)] autorelease];
	[[w contentView] addSubview:in];
	NSRect want = [w convertRectToScreen:[in convertRect:[in bounds] toView:nil]], got = [in accessibilityFrame];
	CHECK(NSEqualRects(got, want), "an NSView's frame is %s, not its screen rectangle %s", [NSStringFromRect(got) UTF8String],
	      [NSStringFromRect(want) UTF8String]);
	[w release];
}

static void cells(void) {
	NSTextFieldCell *c = [[[NSTextFieldCell alloc] initTextCell:@"x"] autorelease];
	element(c, "an NSTextFieldCell", NSAccessibilityStaticTextRole);
	[c setAccessibilityLabel:@"Here"];
	CHECK(same(overridden(c, NSAccessibilityDescriptionAttribute), @"Here"), "an NSCell's label is not its AXDescription override");
	NSRect f = [c accessibilityFrame];
	CHECK(NSEqualRects(f, NSZeroRect), "a cell in no control has frame %s, not NSZeroRect", [NSStringFromRect(f) UTF8String]);
}

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[NSApplication sharedApplication];
	const char *how = argc > 1 ? argv[1] : "";
	BOOL rooted = strcmp(how, "rooted") == 0, own = strcmp(how, "own-view-label") == 0;
	Class view = [NSView class], cell = [NSCell class];
	if (!rooted && !own) {
		/* platform: 10.9 has none of them: NSAccessibility's properties are 10.10 */
		CHECK(members(view) == 0, "an unrooted program's NSView has %d of the accessibility members", members(view));
		CHECK(members(cell) == 0, "an unrooted program's NSCell has %d of the accessibility members", members(cell));
		CHECK(members([NSObject class]) == 0 && members([NSControl class]) == 0, "10.9's NSObject or NSControl has one");
	} else if (own) {
		CHECK([[[[NSView alloc] init] autorelease] accessibilityLabel] != nil, "the program's own -accessibilityLabel was replaced");
		CHECK(members(view) == 1, "with the program's own -accessibilityLabel, NSView has %d members, not just that one",
		      members(view));
		CHECK(members(cell) == (int)NSELS, "the NSCell group did not add its members beside the program's own NSView one");
	} else {
		CHECK(members(view) == (int)NSELS, "a rooted program's NSView has %d of %d members", members(view), (int)NSELS);
		CHECK(members(cell) == (int)NSELS, "a rooted program's NSCell has %d of %d members", members(cell), (int)NSELS);
		if (!failures) {
			encoded(view);
			encoded(cell);
			views();
			cells();
		}
	}
	[pool drain];
	if (failures) return 1;
	printf("objc_accessibility_providers %s: ok\n", rooted ? "rooted" : own ? "own-view-label" : "unrooted");
	return 0;
}
