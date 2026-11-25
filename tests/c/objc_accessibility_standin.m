#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

/* An app shaped like iTerm2 3.2.9's tab elements (PSMTabAccessibilityElementPrototype): it subclasses 10.10's
   NSAccessibilityElement in its own code, links Recaulk's stub libRecaulkAppKit.dylib weakly, and binds the class
   flat and weak, so dyld takes AppKit's class where AppKit has one and Recaulk's stand-in on 10.9.
     with:    the stand-in is beside the program: the subclass realizes and 10.9's attribute API answers from it.
     without: no stand-in: the program still loads, and the subclass is missing (the failure mode). */

/* spec: MacOSX10.10.sdk and later, NSAccessibilityElement.h -- declared here as a 10.9 program declares it */
__attribute__((weak_import))
@interface NSAccessibilityElement : NSObject
+ (id)accessibilityElementWithRole:(NSString *)role frame:(NSRect)frame label:(NSString *)label parent:(id)parent;
- (void)accessibilityAddChildElement:(NSAccessibilityElement *)childElement;
@property NSRect accessibilityFrameInParentSpace;
- (NSString *)accessibilityLabel;
- (void)setAccessibilityLabel:(NSString *)label;
- (NSString *)accessibilityRole;
- (id)accessibilityParent;
- (NSArray *)accessibilityChildren;
- (NSRect)accessibilityFrame;
@end

static int pressed;

@interface TabElement : NSAccessibilityElement
@end
@implementation TabElement
- (NSString *)accessibilityLabel { return @"from the subclass"; }
- (BOOL)accessibilityPerformPress { pressed++; return YES; }
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static BOOL same(id a, id b) { return a == b || [a isEqual:b]; }

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        Class tab = objc_getClass("TabElement");
        if (strcmp(argv[1], "without") == 0) {
            CHECK(tab == Nil, "without the stand-in, TabElement should be missing, not %s", tab ? class_getName(tab) : "");
            CHECK(objc_getClass("RecaulkAccessibilityElement") == Nil, "without the stand-in, its class is present");
            return failures ? 1 : 0;
        }
        if (strcmp(argv[1], "with") != 0) return 2;
        CHECK(tab != Nil, "with the stand-in, TabElement did not realize");
        if (!tab) return 1;
        Class base = class_getSuperclass(tab);
        CHECK(base && strcmp(class_getName(base), "RecaulkAccessibilityElement") == 0,
              "TabElement's superclass is %s, not RecaulkAccessibilityElement", base ? class_getName(base) : "nil");
        CHECK(class_getSuperclass(base) == [NSObject class], "the stand-in is not an NSObject subclass");
        /* spec: Drydock's provided-class rule -- no +load and no +initialize unless declared: the metaclass holds only
           the factory */
        unsigned n = 0;
        Method *ms = class_copyMethodList(object_getClass(base), &n);
        CHECK(n == 1 && ms && sel_isEqual(method_getName(ms[0]), @selector(accessibilityElementWithRole:frame:label:parent:)),
              "the stand-in's metaclass has %u methods, not only the factory", n);
        free(ms);

        NSView *parent = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)] autorelease];
        TabElement *e = [TabElement accessibilityElementWithRole:NSAccessibilityRadioButtonRole
                                                           frame:NSMakeRect(10, 20, 30, 40) label:@"from the factory" parent:parent];
        CHECK([e isKindOfClass:tab], "the factory made a %s, not a TabElement", class_getName([e class]));
        CHECK(same([e accessibilityAttributeValue:NSAccessibilityRoleAttribute], NSAccessibilityRadioButtonRole),
              "AXRole is %s", [[[e accessibilityAttributeValue:NSAccessibilityRoleAttribute] description] UTF8String]);
        CHECK(same([e accessibilityAttributeValue:NSAccessibilityDescriptionAttribute], @"from the subclass"),
              "AXDescription is %s, not the subclass's label",
              [[[e accessibilityAttributeValue:NSAccessibilityDescriptionAttribute] description] UTF8String]);
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
        NSAccessibilityElement *plain = [base accessibilityElementWithRole:NSAccessibilityGroupRole
                                                                     frame:NSMakeRect(100, 100, 50, 50) label:@"plain" parent:parent];
        CHECK(same([plain accessibilityAttributeValue:NSAccessibilityDescriptionAttribute], @"plain"), "the factory's label is lost");
        [plain setAccessibilityLabel:@"relabelled"];
        CHECK(same([plain accessibilityLabel], @"relabelled"), "setAccessibilityLabel: did not store");
        CHECK(![[plain accessibilityActionNames] containsObject:NSAccessibilityPressAction], "a plain element offers AXPress");
        NSAccessibilityElement *child = [base accessibilityElementWithRole:NSAccessibilityButtonRole
                                                                     frame:NSZeroRect label:@"child" parent:nil];
        [plain accessibilityAddChildElement:child];
        CHECK([child accessibilityParent] == plain, "accessibilityAddChildElement: did not make it the child's parent");
        CHECK([[plain accessibilityAttributeValue:NSAccessibilityChildrenAttribute] containsObject:child],
              "AXChildren lacks the added child");
        child.accessibilityFrameInParentSpace = NSMakeRect(5, 6, 10, 12);
        CHECK(NSEqualRects([child accessibilityFrame], NSMakeRect(105, 106, 10, 12)),
              "a frame in parent space is not offset by the parent's frame");
    }
    if (!failures) printf("stand-in: ok\n");
    return failures ? 1 : 0;
}
