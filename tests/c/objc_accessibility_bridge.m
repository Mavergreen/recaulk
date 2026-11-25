#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <recaulk/accessibility.h>
#include <stdio.h>
#include <string.h>

/* Classes shaped like iTerm2 3.2.9's, which implement only 10.10's NSAccessibility protocol getters: a text view (role,
   label, value, text ranges and the parameterized text attributes), a control with a role, children and tabs (an
   NSControl, which 10.9 ignores by default), and a cell. Bridged, 10.9's attribute API answers from those getters. */
@interface TermView : NSView {
@public
	NSRange selected;
	NSArray *setRanges;
}
@end
@implementation TermView
- (NSString *)accessibilityRole { return NSAccessibilityTextAreaRole; }
- (NSString *)accessibilityRoleDescription { return @"terminal"; }
- (NSString *)accessibilityHelp { return @"help"; }
- (NSString *)accessibilityLabel { return @"shell"; }
- (id)accessibilityValue { return @"hello\nworld"; }
- (NSInteger)accessibilityNumberOfCharacters { return 11; }
- (NSString *)accessibilitySelectedText { return @"ell"; }
- (NSRange)accessibilitySelectedTextRange { return selected; }
- (NSArray *)accessibilitySelectedTextRanges { return [NSArray arrayWithObject:[NSValue valueWithRange:selected]]; }
- (void)setAccessibilitySelectedTextRanges:(NSArray *)ranges { setRanges = [ranges retain]; }
- (NSInteger)accessibilityInsertionPointLineNumber { return 1; }
- (NSRange)accessibilityVisibleCharacterRange { return NSMakeRange(0, 11); }
- (NSString *)accessibilityDocument { return @"file:///tmp/x"; }
- (NSRect)accessibilityFrame { return NSMakeRect(5, 6, 7, 8); }
- (NSInteger)accessibilityLineForIndex:(NSInteger)index { return index >= 6 ? 1 : 0; }
- (NSRange)accessibilityRangeForLine:(NSInteger)line { return line ? NSMakeRange(6, 5) : NSMakeRange(0, 6); }
- (NSString *)accessibilityStringForRange:(NSRange)range { return [@"hello\nworld" substringWithRange:range]; }
- (NSRange)accessibilityRangeForPosition:(NSPoint)point { return NSMakeRange((NSUInteger)point.x, 1); }
- (NSRange)accessibilityRangeForIndex:(NSInteger)index { return NSMakeRange((NSUInteger)index, 1); }
- (NSRect)accessibilityFrameForRange:(NSRange)range { return NSMakeRect(range.location, 0, range.length, 10); }
- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range {
	return [[[NSAttributedString alloc] initWithString:[self accessibilityStringForRange:range]] autorelease];
}
@end
@interface SubTermView : TermView
@end
@implementation SubTermView
@end
@interface TabBar : NSControl {
@public
	int pressed;
}
@end
@implementation TabBar
- (NSString *)accessibilityRole { return NSAccessibilityTabGroupRole; }
- (NSArray *)accessibilityChildren { return [NSArray arrayWithObject:@"tab"]; }
- (NSArray *)accessibilityTabs { return [NSArray arrayWithObject:@"tab"]; }
@end
@interface TabCell : NSActionCell {
@public
	int pressed;
}
@end
@implementation TabCell
- (NSString *)accessibilityRole { return NSAccessibilityRadioButtonRole; }
- (NSString *)accessibilityLabel { return @"tab one"; }
- (BOOL)accessibilityPerformPress { pressed++; return YES; }
@end
@interface Plain : NSView
@end
@implementation Plain
@end

/* platform: 10.10's NSAccessibility setters, which Recaulk's NSView group provides when its root is linked */
@interface NSView (RecaulkBridgeTest)
- (void)setAccessibilityLabel:(NSString *)label;
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)
static BOOL same(id a, id b) { return a == b || [a isEqual:b]; }
static const char *str(id x) { return x ? [[x description] UTF8String] : "(nil)"; }
static id value(id e, NSString *attr) {
	@try {
		return [e accessibilityAttributeValue:attr];
	} @catch (NSException *x) {
		return [@"threw " stringByAppendingString:[x name]];
	}
}
static id param(id e, NSString *attr, id p) {
	@try {
		return [e accessibilityAttributeValue:attr forParameter:p];
	} @catch (NSException *x) {
		return [@"threw " stringByAppendingString:[x name]];
	}
}

static const char *members[] = {"accessibilityAttributeNames", "accessibilityAttributeValue:",
	"accessibilityIsAttributeSettable:", "accessibilitySetValue:forAttribute:", "accessibilityParameterizedAttributeNames",
	"accessibilityAttributeValue:forParameter:", "accessibilityActionNames", "accessibilityActionDescription:",
	"accessibilityPerformAction:", "accessibilityIsIgnored"};
#define NMEMBERS (sizeof members / sizeof *members)
static int own(Class c) {
	unsigned n, found = 0;
	Method *list = class_copyMethodList(c, &n);
	for (unsigned i = 0; i < n; i++)
		for (unsigned j = 0; j < NMEMBERS; j++)
			if (strcmp(sel_getName(method_getName(list[i])), members[j]) == 0) found++;
	free(list);
	return (int)found;
}
/* each added member has its floor ancestor's 10.9 encoding */
static void encoded(Class c, Class floor) {
	for (unsigned j = 0; j < NMEMBERS; j++) {
		SEL s = sel_registerName(members[j]);
		Method m = class_getInstanceMethod(c, s), f = class_getInstanceMethod(floor, s);
		CHECK(m && f && strcmp(method_getTypeEncoding(m), method_getTypeEncoding(f)) == 0,
		      "-[%s %s] is encoded %s, not %s's %s", class_getName(c), members[j], m ? method_getTypeEncoding(m) : "-",
		      class_getName(floor), f ? method_getTypeEncoding(f) : "-");
	}
}

static void unbridged(void) {
	TermView *t = [[[TermView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
	CHECK(own([TermView class]) == 0, "an unbridged class has %d of the members", own([TermView class]));
	CHECK([t accessibilityIsIgnored], "10.9 does not ignore a plain NSView subclass");
	CHECK(same(value(t, NSAccessibilityRoleAttribute), NSAccessibilityUnknownRole), "unbridged, the role is %s",
	      str(value(t, NSAccessibilityRoleAttribute)));
	CHECK(![[t accessibilityAttributeNames] containsObject:NSAccessibilityNumberOfCharactersAttribute],
	      "unbridged, 10.9 already lists AXNumberOfCharacters");
}

static void text(TermView *t, const char *what) {
	NSArray *names = [t accessibilityAttributeNames];
	NSString *want[] = {NSAccessibilityRoleAttribute, NSAccessibilityRoleDescriptionAttribute,
		NSAccessibilityDescriptionAttribute, NSAccessibilityValueAttribute, NSAccessibilityHelpAttribute,
		NSAccessibilityNumberOfCharactersAttribute, NSAccessibilitySelectedTextAttribute,
		NSAccessibilitySelectedTextRangeAttribute, NSAccessibilitySelectedTextRangesAttribute,
		NSAccessibilityInsertionPointLineNumberAttribute, NSAccessibilityVisibleCharacterRangeAttribute,
		NSAccessibilityDocumentAttribute, NSAccessibilityPositionAttribute, NSAccessibilitySizeAttribute,
		NSAccessibilityParentAttribute, NSAccessibilityFocusedAttribute};
	for (unsigned i = 0; i < sizeof want / sizeof *want; i++)
		CHECK([names containsObject:want[i]], "%s's attribute names lack %s", what, [want[i] UTF8String]);
	CHECK([names count] == [[NSSet setWithArray:names] count], "%s's attribute names repeat one", what);
	CHECK(![t accessibilityIsIgnored], "%s, which answers a role, is ignored", what);
	CHECK(same(value(t, NSAccessibilityRoleAttribute), NSAccessibilityTextAreaRole), "%s's role is %s", what,
	      str(value(t, NSAccessibilityRoleAttribute)));
	CHECK(same(value(t, NSAccessibilityDescriptionAttribute), @"shell"), "%s's AXDescription is %s, not its label", what,
	      str(value(t, NSAccessibilityDescriptionAttribute)));
	CHECK(same(value(t, NSAccessibilityValueAttribute), @"hello\nworld"), "%s's value is %s", what,
	      str(value(t, NSAccessibilityValueAttribute)));
	CHECK(same(value(t, NSAccessibilityNumberOfCharactersAttribute), [NSNumber numberWithInteger:11]),
	      "%s's AXNumberOfCharacters is %s", what, str(value(t, NSAccessibilityNumberOfCharactersAttribute)));
	t->selected = NSMakeRange(1, 3);
	CHECK(same(value(t, NSAccessibilitySelectedTextRangeAttribute), [NSValue valueWithRange:NSMakeRange(1, 3)]),
	      "%s's AXSelectedTextRange is %s", what, str(value(t, NSAccessibilitySelectedTextRangeAttribute)));
	CHECK(same(value(t, NSAccessibilityPositionAttribute), [NSValue valueWithPoint:NSMakePoint(5, 6)]) &&
	          same(value(t, NSAccessibilitySizeAttribute), [NSValue valueWithSize:NSMakeSize(7, 8)]),
	      "%s's AXPosition and AXSize are %s and %s, not its frame's", what, str(value(t, NSAccessibilityPositionAttribute)),
	      str(value(t, NSAccessibilitySizeAttribute)));
	/* an attribute no 10.10 getter of its answers falls back to 10.9's */
	CHECK(same(value(t, NSAccessibilityFocusedAttribute), [NSNumber numberWithBool:NO]), "%s's AXFocused is %s, not 10.9's",
	      what, str(value(t, NSAccessibilityFocusedAttribute)));

	NSArray *pnames = [t accessibilityParameterizedAttributeNames];
	NSString *pwant[] = {NSAccessibilityLineForIndexParameterizedAttribute, NSAccessibilityRangeForLineParameterizedAttribute,
		NSAccessibilityStringForRangeParameterizedAttribute, NSAccessibilityRangeForPositionParameterizedAttribute,
		NSAccessibilityRangeForIndexParameterizedAttribute, NSAccessibilityBoundsForRangeParameterizedAttribute,
		NSAccessibilityAttributedStringForRangeParameterizedAttribute};
	for (unsigned i = 0; i < sizeof pwant / sizeof *pwant; i++)
		CHECK([pnames containsObject:pwant[i]], "%s's parameterized names lack %s", what, [pwant[i] UTF8String]);
	NSValue *r = [NSValue valueWithRange:NSMakeRange(6, 5)];
	CHECK(same(param(t, NSAccessibilityStringForRangeParameterizedAttribute, r), @"world"), "%s's AXStringForRange is %s",
	      what, str(param(t, NSAccessibilityStringForRangeParameterizedAttribute, r)));
	CHECK(same(param(t, NSAccessibilityLineForIndexParameterizedAttribute, [NSNumber numberWithInteger:7]),
	           [NSNumber numberWithInteger:1]),
	      "%s's AXLineForIndex is %s", what,
	      str(param(t, NSAccessibilityLineForIndexParameterizedAttribute, [NSNumber numberWithInteger:7])));
	CHECK(same(param(t, NSAccessibilityRangeForLineParameterizedAttribute, [NSNumber numberWithInteger:1]), r),
	      "%s's AXRangeForLine is %s", what,
	      str(param(t, NSAccessibilityRangeForLineParameterizedAttribute, [NSNumber numberWithInteger:1])));
	CHECK(same(param(t, NSAccessibilityRangeForPositionParameterizedAttribute, [NSValue valueWithPoint:NSMakePoint(4, 0)]),
	           [NSValue valueWithRange:NSMakeRange(4, 1)]),
	      "%s's AXRangeForPosition is wrong", what);
	CHECK(same(param(t, NSAccessibilityBoundsForRangeParameterizedAttribute, r),
	           [NSValue valueWithRect:NSMakeRect(6, 0, 5, 10)]),
	      "%s's AXBoundsForRange is %s", what, str(param(t, NSAccessibilityBoundsForRangeParameterizedAttribute, r)));
	CHECK([[param(t, NSAccessibilityAttributedStringForRangeParameterizedAttribute, r) string] isEqual:@"world"],
	      "%s's AXAttributedStringForRange is wrong", what);

	NSArray *ranges = [NSArray arrayWithObject:[NSValue valueWithRange:NSMakeRange(0, 2)]];
	CHECK([t accessibilityIsAttributeSettable:NSAccessibilitySelectedTextRangesAttribute],
	      "%s's AXSelectedTextRanges is not settable, though it has the 10.10 setter", what);
	[t accessibilitySetValue:ranges forAttribute:NSAccessibilitySelectedTextRangesAttribute];
	CHECK(same(t->setRanges, ranges), "%s's AXSelectedTextRanges did not reach setAccessibilitySelectedTextRanges:", what);
	CHECK(![t accessibilityIsAttributeSettable:NSAccessibilityNumberOfCharactersAttribute],
	      "%s's AXNumberOfCharacters is settable", what);
}

static void bridged(BOOL setters) {
	Class term = [TermView class], bar = [TabBar class], cell = [TabCell class];
	unsigned before = 0;
	free(class_copyMethodList([Plain class], &before));
	recaulk_accessibility_bridge(Nil);
	recaulk_accessibility_bridge(term);
	recaulk_accessibility_bridge(bar);
	recaulk_accessibility_bridge(cell);
	unsigned after = 0;
	free(class_copyMethodList([Plain class], &after));
	CHECK(before == after && own([Plain class]) == 0, "bridging Nil or other classes added to an unbridged class");
	CHECK(own(term) == (int)NMEMBERS && own(bar) == (int)NMEMBERS && own(cell) == (int)NMEMBERS,
	      "a bridged class has %d, %d, %d of %d members", own(term), own(bar), own(cell), (int)NMEMBERS);
	CHECK(own([SubTermView class]) == 0, "a bridged class's subclass got members of its own");
	if (failures) return;
	encoded(term, [NSView class]);
	encoded(bar, [NSView class]);
	encoded(cell, [NSCell class]);

	text([[[TermView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease], "a bridged text view");
	/* the super walk: a subclass of a bridged class reaches 10.9's NSView, not itself */
	text([[[SubTermView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease], "a bridged text view's subclass");

	TabBar *b = [[[TabBar alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)] autorelease];
	CHECK(![b accessibilityIsIgnored], "a bridged NSControl with a role is ignored, as 10.9 ignores controls");
	CHECK(same(value(b, NSAccessibilityRoleAttribute), NSAccessibilityTabGroupRole), "the tab bar's role is %s",
	      str(value(b, NSAccessibilityRoleAttribute)));
	CHECK(same(value(b, NSAccessibilityChildrenAttribute), [NSArray arrayWithObject:@"tab"]) &&
	          same(value(b, NSAccessibilityTabsAttribute), [NSArray arrayWithObject:@"tab"]),
	      "the tab bar's children or tabs are wrong: %s, %s", str(value(b, NSAccessibilityChildrenAttribute)),
	      str(value(b, NSAccessibilityTabsAttribute)));
	CHECK([[b accessibilityAttributeNames] containsObject:NSAccessibilityTabsAttribute], "the tab bar does not list AXTabs");
	CHECK(![[b accessibilityActionNames] containsObject:NSAccessibilityPressAction],
	      "the tab bar lists AXPress, which it does not implement");

	TabCell *c = [[[TabCell alloc] initTextCell:@"one"] autorelease];
	CHECK(same(value(c, NSAccessibilityRoleAttribute), NSAccessibilityRadioButtonRole), "the tab cell's role is %s",
	      str(value(c, NSAccessibilityRoleAttribute)));
	CHECK(same(value(c, NSAccessibilityDescriptionAttribute), @"tab one"), "the tab cell's AXDescription is %s",
	      str(value(c, NSAccessibilityDescriptionAttribute)));
	CHECK([[c accessibilityActionNames] containsObject:NSAccessibilityPressAction], "the tab cell does not list AXPress");
	CHECK(same([c accessibilityActionDescription:NSAccessibilityPressAction], NSAccessibilityActionDescription(NSAccessibilityPressAction)),
	      "the tab cell's AXPress description is %s", str([c accessibilityActionDescription:NSAccessibilityPressAction]));
	[c accessibilityPerformAction:NSAccessibilityPressAction];
	CHECK(c->pressed == 1, "AXPress did not call accessibilityPerformPress (%d calls)", c->pressed);

	if (setters) {
		/* With Recaulk's NSView setter group linked, every view answers -accessibilityLabel through 10.9's attribute
		   API, which the bridge in turn answers from -accessibilityLabel: neither may loop, and a label set on a bridged
		   view without its own getter reads back as its AXDescription. */
		Class lone = objc_allocateClassPair([NSView class], "RecaulkBridgeLoneView", 0);
		objc_registerClassPair(lone);
		recaulk_accessibility_bridge(lone);
		NSView *v = [[[lone alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
		[v setAccessibilityLabel:@"set"];
		CHECK(same(value(v, NSAccessibilityRoleAttribute), NSAccessibilityUnknownRole), "a getterless bridged view's role is %s",
		      str(value(v, NSAccessibilityRoleAttribute)));
		CHECK([[v accessibilityAttributeNames] containsObject:NSAccessibilityRoleAttribute],
		      "a getterless bridged view lost 10.9's attribute names");
		CHECK([v accessibilityIsIgnored], "a getterless bridged view is no longer ignored, as 10.9 ignores it");
	}
}

/* platform: 10.9's accessibility server reaches a process's elements only with assistive access (System Preferences,
   Security & Privacy, Accessibility); without it there is nothing to ask, so this says so and checks nothing */
static void server(void) {
	if (!AXIsProcessTrusted()) {
		printf("objc_accessibility_bridge: no assistive access here, so the AX server's view is unchecked\n");
		return;
	}
	printf("objc_accessibility_bridge: assistive access present; the AX server path is not exercised by this test\n");
}

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[NSApplication sharedApplication];
	const char *how = argc > 1 ? argv[1] : "";
	if (strcmp(how, "unbridged") == 0) unbridged();
	else if (strcmp(how, "bridged") == 0) bridged(NO);
	else if (strcmp(how, "bridged-with-setters") == 0) bridged(YES);
	else CHECK(0, "usage: objc_accessibility_bridge unbridged|bridged|bridged-with-setters");
	server();
	[pool drain];
	if (failures) return 1;
	printf("objc_accessibility_bridge %s: ok\n", how);
	return 0;
}
