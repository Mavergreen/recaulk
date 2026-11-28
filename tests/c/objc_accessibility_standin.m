#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

/* An app shaped like iTerm2 3.2.9's tab elements (PSMTabAccessibilityElementPrototype) after Drydock retargets them:
   the subclass's class and metaclass bind Recaulk's shim, RecaulkAccessibilityElement, two-level in
   libRecaulkAppKit.dylib. Each mode is one branch of the shim's constructor:
     standin:  no NSAccessibilityElement (10.9): the stand-in's methods serve the subclass;
     reparent: a fake NSAccessibilityElement loaded first, as 10.10's AppKit would be: the shim now inherits from it,
               and Recaulk added nothing;
     fallback: the fake is there but the re-parent failed (the shell checks the line): the stand-in serves, on NSObject;
     conflict: a category on the shim already has accessibilityRole, so the stand-in's cannot land (the shell checks
               the line): the category's answers, and the other members still serve. */

/* spec: README.md "Stand-in classes" -- the installed header declares the shim; the app declares nothing itself */
#import <recaulk/accessibility-element.h>

static int pressed;

@interface TabElement : RecaulkAccessibilityElement
@end
@implementation TabElement
- (NSString *)accessibilityLabel { return @"from the subclass"; }
- (BOOL)accessibilityPerformPress { pressed++; return YES; }
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static BOOL same(id a, id b) { return a == b || [a isEqual:b]; }
static const char *str(id o) { return o ? [[o description] UTF8String] : "nil"; }
static unsigned count(Class c) { unsigned n = 0; free(class_copyMethodList(c, &n)); return n; }

static void standin(Class tab, Class base) {
    CHECK(class_getSuperclass(base) == [NSObject class], "the shim's superclass is %s, not NSObject",
          class_getName(class_getSuperclass(base)));
    /* spec: Drydock's provided-class design, check 4 -- only the declared members, the factory on the metaclass */
    unsigned n = 0;
    Method *ms = class_copyMethodList(object_getClass(base), &n);
    CHECK(n == 1 && ms && sel_isEqual(method_getName(ms[0]), @selector(accessibilityElementWithRole:frame:label:parent:)),
          "the shim's metaclass has %u methods, not only the factory", n);
    free(ms);

    NSView *parent = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)] autorelease];
    TabElement *e = [TabElement accessibilityElementWithRole:NSAccessibilityRadioButtonRole
                                                       frame:NSMakeRect(10, 20, 30, 40) label:@"from the factory" parent:parent];
    CHECK([e isKindOfClass:tab], "the factory made a %s, not a TabElement", class_getName([e class]));
    CHECK(same([e accessibilityAttributeValue:NSAccessibilityRoleAttribute], NSAccessibilityRadioButtonRole),
          "AXRole is %s", str([e accessibilityAttributeValue:NSAccessibilityRoleAttribute]));
    CHECK(same([e accessibilityAttributeValue:NSAccessibilityDescriptionAttribute], @"from the subclass"),
          "AXDescription is %s, not the subclass's label", str([e accessibilityAttributeValue:NSAccessibilityDescriptionAttribute]));
    CHECK([e accessibilityAttributeValue:NSAccessibilityParentAttribute] == parent, "AXParent is not the parent view");
    CHECK(NSEqualPoints([[e accessibilityAttributeValue:NSAccessibilityPositionAttribute] pointValue], NSMakePoint(10, 20)),
          "AXPosition is not the frame's origin");
    CHECK(NSEqualSizes([[e accessibilityAttributeValue:NSAccessibilitySizeAttribute] sizeValue], NSMakeSize(30, 40)),
          "AXSize is not the frame's size");
    NSArray *names = [e accessibilityAttributeNames];
    for (NSString *a in [NSArray arrayWithObjects:NSAccessibilityRoleAttribute, NSAccessibilityDescriptionAttribute,
                         NSAccessibilityParentAttribute, NSAccessibilityPositionAttribute, NSAccessibilitySizeAttribute, nil])
        CHECK([names containsObject:a], "accessibilityAttributeNames lacks %s", [a UTF8String]);
    CHECK(![e accessibilityIsIgnored], "the element is ignored");
    CHECK([[e accessibilityActionNames] containsObject:NSAccessibilityPressAction], "AXPress is not offered");
    [e accessibilityPerformAction:NSAccessibilityPressAction];
    CHECK(pressed == 1, "AXPress did not reach the subclass's accessibilityPerformPress (%d)", pressed);

    /* the stand-in's own storage, where no subclass overrides */
    RecaulkAccessibilityElement *plain = [base accessibilityElementWithRole:NSAccessibilityGroupRole
                                                                     frame:NSMakeRect(100, 100, 50, 50) label:@"plain" parent:parent];
    CHECK(same([plain accessibilityAttributeValue:NSAccessibilityDescriptionAttribute], @"plain"), "the factory's label is lost");
    [plain setAccessibilityLabel:@"relabelled"];
    CHECK(same([plain accessibilityLabel], @"relabelled"), "setAccessibilityLabel: did not store");
    CHECK(![[plain accessibilityActionNames] containsObject:NSAccessibilityPressAction], "a plain element offers AXPress");
    RecaulkAccessibilityElement *child = [base accessibilityElementWithRole:NSAccessibilityButtonRole
                                                                     frame:NSZeroRect label:@"child" parent:nil];
    [plain accessibilityAddChildElement:child];
    CHECK([child accessibilityParent] == plain, "accessibilityAddChildElement: did not make it the child's parent");
    CHECK([[plain accessibilityAttributeValue:NSAccessibilityChildrenAttribute] containsObject:child],
          "AXChildren lacks the added child");
    child.accessibilityFrameInParentSpace = NSMakeRect(5, 6, 10, 12);
    CHECK(NSEqualRects([child accessibilityFrame], NSMakeRect(105, 106, 10, 12)),
          "a frame in parent space is not offset by the parent's frame");
}

static void reparent(Class tab, Class base) {
    Class target = objc_getClass("NSAccessibilityElement");
    CHECK(target != Nil, "the fake NSAccessibilityElement is not loaded");
    CHECK(class_getSuperclass(base) == target, "the shim's superclass is %s, not NSAccessibilityElement",
          class_getName(class_getSuperclass(base)));
    CHECK(class_getSuperclass(target) == [NSObject class], "the fake is not an NSObject subclass");
    /* spec: Drydock's provided-class design, check 3 -- the success path adds no method */
    CHECK(count(base) == 0 && count(object_getClass(base)) == 0, "the shim gained methods (%u, +%u) on the success path",
          count(base), count(object_getClass(base)));
    TabElement *e = [[[TabElement alloc] init] autorelease];
    CHECK([e isKindOfClass:target], "a TabElement is not an NSAccessibilityElement");
    CHECK(same([e accessibilityRole], @"from the fake"), "accessibilityRole is %s, not the target's", str([e accessibilityRole]));
    CHECK(same([e accessibilityLabel], @"from the subclass"), "the subclass's override lost to %s", str([e accessibilityLabel]));
    CHECK(![e respondsToSelector:@selector(accessibilityAttributeNames)], "a Recaulk method serves the re-parented shim");
    (void)tab;
}

static void conflict(Class tab, Class base) {
    (void)tab;
    RecaulkAccessibilityElement *e = [base accessibilityElementWithRole:NSAccessibilityGroupRole
                                                                 frame:NSZeroRect label:@"still served" parent:nil];
    CHECK(same([e accessibilityRole], @"from the category"), "accessibilityRole is %s, not the category's", str([e accessibilityRole]));
    CHECK(same([e accessibilityLabel], @"still served"), "the members that could land did not (%s)", str([e accessibilityLabel]));
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        Class tab = objc_getClass("TabElement");
        CHECK(tab != Nil, "TabElement did not realize");
        if (!tab) return 1;
        Class base = class_getSuperclass(tab);
        CHECK(base && strcmp(class_getName(base), "RecaulkAccessibilityElement") == 0,
              "TabElement's superclass is %s, not RecaulkAccessibilityElement", base ? class_getName(base) : "nil");
        if (!base) return 1;
        if (strcmp(argv[1], "standin") == 0 || strcmp(argv[1], "fallback") == 0) {
            CHECK((objc_getClass("NSAccessibilityElement") != Nil) == (strcmp(argv[1], "fallback") == 0),
                  "NSAccessibilityElement is %s in %s", objc_getClass("NSAccessibilityElement") ? "present" : "absent", argv[1]);
            standin(tab, base);
        } else if (strcmp(argv[1], "reparent") == 0) {
            reparent(tab, base);
        } else if (strcmp(argv[1], "conflict") == 0) {
            conflict(tab, base);
        } else {
            return 2;
        }
    }
    if (!failures) printf("%s: ok\n", argv[1]);
    return failures ? 1 : 0;
}
