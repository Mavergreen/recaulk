/* RecaulkAccessibilityElement: a shim an app subclasses in place of 10.10's NSAccessibilityElement, which 10.9 lacks.
 *
 * spec: Drydock's provided-class design ("Deferring to the OS's class: a re-parenting shim", 2026-11-24), section 1.
 * The class always exists, so a subclass bound to it two-level never loses its superclass. It has no compiled methods,
 * no ivars, no protocols, no properties, no +load and no +initialize. This image's one constructor picks a branch:
 *   - where AppKit has NSAccessibilityElement (10.10 and later), it re-parents the shim onto AppKit's class with the
 *     weak-imported class_setSuperclass and verifies it took; AppKit then serves every method and no Recaulk code runs;
 *   - otherwise (10.9), or when the re-parent is unavailable or doesn't verify, it realizes the shim and adds the
 *     stand-in's methods to it, state in associated objects: 10.10's API, and 10.9's attribute API answered from the
 *     10.10 getters (accessibility-map.h, shared with the bridge), a subclass's overrides first.
 * Every failure prints one line through NSLog and falls through to the stand-in. RECAULK_DISABLE_REPARENT in the
 * environment forces the stand-in. */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdlib.h>
#import "accessibility-map.h"

#if !__has_feature(objc_arc)
#error "build/build-standins.sh compiles the stand-ins with ARC"
#endif

@interface RecaulkAccessibilityElement : NSObject
@end
@implementation RecaulkAccessibilityElement
@end

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
/* platform: class_setSuperclass is deprecated (objc/runtime.h); weak, so a libobjc without it binds NULL, not a crash */
extern Class class_setSuperclass(Class cls, Class newSuper) __attribute__((weak_import));
/* spec: the design's section 1 -- the class object by symbol: a message or objc_getClass would realize it too early */
extern char RecaulkShimClass __asm__("_OBJC_CLASS_$_RecaulkAccessibilityElement");

/* The stand-in's state, one associated object per property, keyed by these statics' addresses (the shim has no ivars). */
static char kRole, kSubrole, kRoleDescription, kLabel, kTitle, kHelp, kIdentifier, kValue, kParent, kChildren, kFrame,
    kFrameInParent, kDisabled, kNotElement, kFocused, kSelected;

static id get(id self, const void *key) { return objc_getAssociatedObject(self, key); }
static void put(id self, const void *key, id v) { objc_setAssociatedObject(self, key, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void putCopy(id self, const void *key, id v) { objc_setAssociatedObject(self, key, v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
static BOOL flag(id self, const void *key) { return [(NSNumber *)get(self, key) boolValue]; }
static void putFlag(id self, const void *key, BOOL b) { put(self, key, b ? [NSNumber numberWithBool:YES] : nil); }

/* spec: MacOSX10.10.sdk NSAccessibilityElement.h -- the factory, with the frame in screen coordinates */
static id sa_element(Class self, SEL _cmd, NSString *role, NSRect frame, NSString *label, id parent) {
    (void)_cmd;
    id e = [[self alloc] init];
    putCopy(e, &kRole, role);
    put(e, &kFrame, [NSValue valueWithRect:frame]);
    putCopy(e, &kLabel, label);
    /* platform: not retained, as NSAccessibilityElement.h asks the vendor to keep an element's parent alive */
    objc_setAssociatedObject(e, &kParent, parent, OBJC_ASSOCIATION_ASSIGN);
    return e;
}
static void sa_addChild(id self, SEL _cmd, id child) {
    (void)_cmd;
    if (!child) return;
    NSArray *now = get(self, &kChildren);
    put(self, &kChildren, now ? [now arrayByAddingObject:child] : [NSArray arrayWithObject:child]);
    objc_setAssociatedObject(child, &kParent, self, OBJC_ASSOCIATION_ASSIGN);
}
static NSRect sa_frameInParentSpace(id self, SEL _cmd) {
    (void)_cmd;
    NSValue *v = get(self, &kFrameInParent);
    return v ? [v rectValue] : NSZeroRect;
}
static void sa_setFrameInParentSpace(id self, SEL _cmd, NSRect r) { (void)_cmd; put(self, &kFrameInParent, [NSValue valueWithRect:r]); }
/* platform: 10.10's element in parent space is offset by its parent's screen frame */
static NSRect sa_frame(id self, SEL _cmd) {
    (void)_cmd;
    NSValue *inParent = get(self, &kFrameInParent);
    if (!inParent) {
        NSValue *v = get(self, &kFrame);
        return v ? [v rectValue] : NSZeroRect;
    }
    NSObject *parent = get(self, &kParent);
    NSPoint at = NSZeroPoint;
    if ([parent respondsToSelector:@selector(accessibilityFrame)]) {
        at = [parent accessibilityFrame].origin;
    } else if ([parent respondsToSelector:@selector(accessibilityAttributeValue:)]) {
        NSValue *p = [parent accessibilityAttributeValue:NSAccessibilityPositionAttribute];
        if ([p isKindOfClass:[NSValue class]]) at = [p pointValue];
    }
    return NSOffsetRect([inParent rectValue], at.x, at.y);
}
static void sa_setFrame(id self, SEL _cmd, NSRect r) {
    (void)_cmd;
    put(self, &kFrame, [NSValue valueWithRect:r]);
    put(self, &kFrameInParent, nil);
}

#define STRING(name, setter, key) \
    static id sa_##name(id self, SEL _cmd) { (void)_cmd; return get(self, &key); } \
    static void sa_##setter(id self, SEL _cmd, id v) { (void)_cmd; putCopy(self, &key, v); }
STRING(role, setRole, kRole)
STRING(subrole, setSubrole, kSubrole)
STRING(label, setLabel, kLabel)
STRING(title, setTitle, kTitle)
STRING(help, setHelp, kHelp)
STRING(identifier, setIdentifier, kIdentifier)
STRING(children, setChildren, kChildren)
#undef STRING
static id sa_roleDescription(id self, SEL _cmd) {
    (void)_cmd;
    NSString *d = get(self, &kRoleDescription), *role = get(self, &kRole);
    return d ? d : role ? NSAccessibilityRoleDescription(role, get(self, &kSubrole)) : nil;
}
static void sa_setRoleDescription(id self, SEL _cmd, id v) { (void)_cmd; putCopy(self, &kRoleDescription, v); }
static id sa_value(id self, SEL _cmd) { (void)_cmd; return get(self, &kValue); }
static void sa_setValue(id self, SEL _cmd, id v) { (void)_cmd; put(self, &kValue, v); }
static id sa_parent(id self, SEL _cmd) { (void)_cmd; return get(self, &kParent); }
static void sa_setParent(id self, SEL _cmd, id v) { (void)_cmd; objc_setAssociatedObject(self, &kParent, v, OBJC_ASSOCIATION_ASSIGN); }
/* inverted where 10.10's default is YES, so an element nobody configured is enabled and is an element */
static BOOL sa_enabled(id self, SEL _cmd) { (void)_cmd; return !flag(self, &kDisabled); }
static void sa_setEnabled(id self, SEL _cmd, BOOL b) { (void)_cmd; putFlag(self, &kDisabled, !b); }
static BOOL sa_focused(id self, SEL _cmd) { (void)_cmd; return flag(self, &kFocused); }
static void sa_setFocused(id self, SEL _cmd, BOOL b) { (void)_cmd; putFlag(self, &kFocused, b); }
static BOOL sa_selected(id self, SEL _cmd) { (void)_cmd; return flag(self, &kSelected); }
static void sa_setSelected(id self, SEL _cmd, BOOL b) { (void)_cmd; putFlag(self, &kSelected, b); }
static BOOL sa_element_(id self, SEL _cmd) { (void)_cmd; return !flag(self, &kNotElement); }
static void sa_setElement(id self, SEL _cmd, BOOL b) { (void)_cmd; putFlag(self, &kNotElement, !b); }
/* platform: an element's window is its parent's, which on 10.9 is a view answering the attribute API */
static id sa_window(id self, SEL _cmd) {
    (void)_cmd;
    NSObject *parent = get(self, &kParent);
    return [parent respondsToSelector:@selector(accessibilityAttributeValue:)]
        ? [parent accessibilityAttributeValue:NSAccessibilityWindowAttribute] : nil;
}
static id sa_topLevel(id self, SEL _cmd) {
    (void)_cmd;
    NSObject *parent = get(self, &kParent);
    return [parent respondsToSelector:@selector(accessibilityAttributeValue:)]
        ? [parent accessibilityAttributeValue:NSAccessibilityTopLevelUIElementAttribute] : nil;
}

/* 10.9's attribute API, from the getters above or a subclass's (accessibility-map.h) */
static NSArray *sa_attributeNames(id self, SEL _cmd) {
    (void)_cmd;
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *a in mappedAttributes())
        if (answer(self, a)) [names addObject:a];
    return names;
}
static id sa_attributeValue(id self, SEL _cmd, NSString *a) { (void)_cmd; return answer(self, a); }
static BOOL sa_isSettable(id self, SEL _cmd, NSString *a) { (void)_cmd; return settable(self, a); }
static void sa_setAttribute(id self, SEL _cmd, id value, NSString *a) {
    (void)_cmd;
    /* spec: tests/objc-source-receipt.sh -- a typed view of the value, so no send has a receiver of type id */
    NSNumber *b = [value isKindOfClass:[NSNumber class]] ? value : nil;
    NSObject *me = self;
    if ([a isEqualToString:NSAccessibilityValueAttribute]) [me setAccessibilityValue:value];
    else if ([a isEqualToString:NSAccessibilityFocusedAttribute]) [me setAccessibilityFocused:[b boolValue]];
    else if ([a isEqualToString:NSAccessibilitySelectedAttribute]) [me setAccessibilitySelected:[b boolValue]];
}
static NSArray *sa_actionNames(id self, SEL _cmd) {
    (void)_cmd;
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *a in [NSArray arrayWithObjects:NSAccessibilityPressAction, NSAccessibilityCancelAction,
             NSAccessibilityConfirmAction, NSAccessibilityDecrementAction, NSAccessibilityDeleteAction,
             NSAccessibilityIncrementAction, NSAccessibilityPickAction, NSAccessibilityRaiseAction,
             NSAccessibilityShowAlternateUIAction, NSAccessibilityShowDefaultUIAction, NSAccessibilityShowMenuAction, nil]) {
        BOOL known = NO;
        action(self, a, NO, &known);
        if (known) [names addObject:a];
    }
    return names;
}
static id sa_actionDescription(id self, SEL _cmd, NSString *name) {
    (void)_cmd;
    BOOL known = NO;
    action(self, name, NO, &known);
    return known ? NSAccessibilityActionDescription(name) : nil;
}
static void sa_performAction(id self, SEL _cmd, NSString *name) {
    (void)_cmd;
    BOOL known = NO;
    action(self, name, YES, &known);
}
static BOOL sa_isIgnored(id self, SEL _cmd) { (void)_cmd; return ![(NSObject *)self isAccessibilityElement]; }
static id sa_hitTest(id self, SEL _cmd, NSPoint p) { (void)_cmd; (void)p; return self; }
static id sa_focusedUIElement(id self, SEL _cmd) { (void)_cmd; return self; }

#define NSRECT "{CGRect={CGPoint=dd}{CGSize=dd}}"
/* spec: the design's check 4 -- realize first (objc4-551's class_addMethod silently does nothing on an unrealized
   class), then add each declared member with a literal selector, implementation and type, then check each landed */
static void install_standin(Class shim) {
    (void)class_getInstanceMethod(shim, sel_registerName("description"));
    Class meta = object_getClass((id)shim);
    BOOL landed = YES;
#define ADD(cls, sel, imp, types) \
    class_addMethod(cls, sel_registerName(sel), (IMP)imp, types); \
    landed = landed && class_getMethodImplementation(cls, sel_registerName(sel)) == (IMP)imp
    ADD(meta, "accessibilityElementWithRole:frame:label:parent:", sa_element, "@72@0:8@16" NSRECT "24@56@64");
    ADD(shim, "accessibilityAddChildElement:", sa_addChild, "v24@0:8@16");
    ADD(shim, "accessibilityFrameInParentSpace", sa_frameInParentSpace, NSRECT "16@0:8");
    ADD(shim, "setAccessibilityFrameInParentSpace:", sa_setFrameInParentSpace, "v48@0:8" NSRECT "16");
    ADD(shim, "accessibilityFrame", sa_frame, NSRECT "16@0:8");
    ADD(shim, "setAccessibilityFrame:", sa_setFrame, "v48@0:8" NSRECT "16");
    ADD(shim, "accessibilityRole", sa_role, "@16@0:8");
    ADD(shim, "setAccessibilityRole:", sa_setRole, "v24@0:8@16");
    ADD(shim, "accessibilitySubrole", sa_subrole, "@16@0:8");
    ADD(shim, "setAccessibilitySubrole:", sa_setSubrole, "v24@0:8@16");
    ADD(shim, "accessibilityRoleDescription", sa_roleDescription, "@16@0:8");
    ADD(shim, "setAccessibilityRoleDescription:", sa_setRoleDescription, "v24@0:8@16");
    ADD(shim, "accessibilityLabel", sa_label, "@16@0:8");
    ADD(shim, "setAccessibilityLabel:", sa_setLabel, "v24@0:8@16");
    ADD(shim, "accessibilityTitle", sa_title, "@16@0:8");
    ADD(shim, "setAccessibilityTitle:", sa_setTitle, "v24@0:8@16");
    ADD(shim, "accessibilityHelp", sa_help, "@16@0:8");
    ADD(shim, "setAccessibilityHelp:", sa_setHelp, "v24@0:8@16");
    ADD(shim, "accessibilityIdentifier", sa_identifier, "@16@0:8");
    ADD(shim, "setAccessibilityIdentifier:", sa_setIdentifier, "v24@0:8@16");
    ADD(shim, "accessibilityValue", sa_value, "@16@0:8");
    ADD(shim, "setAccessibilityValue:", sa_setValue, "v24@0:8@16");
    ADD(shim, "accessibilityParent", sa_parent, "@16@0:8");
    ADD(shim, "setAccessibilityParent:", sa_setParent, "v24@0:8@16");
    ADD(shim, "accessibilityChildren", sa_children, "@16@0:8");
    ADD(shim, "setAccessibilityChildren:", sa_setChildren, "v24@0:8@16");
    ADD(shim, "isAccessibilityEnabled", sa_enabled, "c16@0:8");
    ADD(shim, "setAccessibilityEnabled:", sa_setEnabled, "v20@0:8c16");
    ADD(shim, "isAccessibilityFocused", sa_focused, "c16@0:8");
    ADD(shim, "setAccessibilityFocused:", sa_setFocused, "v20@0:8c16");
    ADD(shim, "isAccessibilitySelected", sa_selected, "c16@0:8");
    ADD(shim, "setAccessibilitySelected:", sa_setSelected, "v20@0:8c16");
    ADD(shim, "isAccessibilityElement", sa_element_, "c16@0:8");
    ADD(shim, "setAccessibilityElement:", sa_setElement, "v20@0:8c16");
    ADD(shim, "accessibilityWindow", sa_window, "@16@0:8");
    ADD(shim, "accessibilityTopLevelUIElement", sa_topLevel, "@16@0:8");
    ADD(shim, "accessibilityAttributeNames", sa_attributeNames, "@16@0:8");
    ADD(shim, "accessibilityAttributeValue:", sa_attributeValue, "@24@0:8@16");
    ADD(shim, "accessibilityIsAttributeSettable:", sa_isSettable, "c24@0:8@16");
    ADD(shim, "accessibilitySetValue:forAttribute:", sa_setAttribute, "v32@0:8@16@24");
    ADD(shim, "accessibilityActionNames", sa_actionNames, "@16@0:8");
    ADD(shim, "accessibilityActionDescription:", sa_actionDescription, "@24@0:8@16");
    ADD(shim, "accessibilityPerformAction:", sa_performAction, "v24@0:8@16");
    ADD(shim, "accessibilityIsIgnored", sa_isIgnored, "c16@0:8");
    ADD(shim, "accessibilityHitTest:", sa_hitTest, "@32@0:8{CGPoint=dd}16");
    ADD(shim, "accessibilityFocusedUIElement", sa_focusedUIElement, "@16@0:8");
#undef ADD
    if (!landed)
        NSLog(@"Recaulk: cannot install the stand-in methods on RecaulkAccessibilityElement; its subclasses' accessibility "
              @"will not work on this macOS.");
}

/* spec: the design's section 1, the constructor's shape -- this image's only initializer */
__attribute__((constructor)) static void recaulk_accessibility_element_init(void) {
    Class shim = (__bridge Class)(void *)&RecaulkShimClass;
    Class real = objc_getClass("NSAccessibilityElement");
    if (!real) {
        install_standin(shim);
        return;
    }
    const char *reason = NULL;
    Class (*setsuper)(Class, Class) = class_setSuperclass;
    if (getenv("RECAULK_DISABLE_REPARENT")) setsuper = NULL;
    if (!setsuper) {
        reason = "class_setSuperclass is unavailable";
    } else {
        Class old = setsuper(shim, real);
        (void)class_getInstanceMethod(shim, sel_registerName("description"));
        if (class_getSuperclass(shim) != real)
            reason = "the superclass did not change";
        else if (class_getInstanceSize(shim) < class_getInstanceSize(real))
            reason = "the shim was realized before this constructor, with NSObject's instance layout";
        if (reason) setsuper(shim, old);
    }
    if (!reason) return;
    NSLog(@"Recaulk: cannot re-parent RecaulkAccessibilityElement onto NSAccessibilityElement (%s); falling back to the "
          @"built-in stand-in.", reason);
    install_standin(shim);
}
