/* The accessibility bridge: 10.9's VoiceOver asks an element only through the old attribute API
 * (accessibilityAttributeNames, accessibilityAttributeValue: and their kin), while an app written for 10.10 or later
 * may implement only the NSAccessibility protocol's getters (accessibilityRole, accessibilityLabel, ...). An app calls
 * recaulk_accessibility_bridge once per such class, and that class's old API then answers from its 10.10 getters, and
 * from 10.9's own (a super send of the same selector) for anything its getters don't answer.
 *
 * The shape is the one Drydock verifies (README.md "Objective-C methods", the accessibility bridge): the root only adds
 * each member to the class it is given, with a literal selector, implementation and 10.9 type, and nothing calls it but
 * the app. Each member is one 10.9 NSView and NSCell already have (their floor), so an add overrides that class's
 * inherited 10.9 method, which the super send then reaches. */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "accessibility-map.h"

/* spec: src/include/recaulk/accessibility.h -- the public declaration, repeated here because the source receipt reads
   only this directory's inputs; tests/objc-accessibility-bridge.sh links a program compiled against that header */
void recaulk_accessibility_bridge(Class cls);

/* The classes the app has bridged, in the order bridged, then Nil: one data symbol, Drydock's class_table, which only
   the root writes and only with its class argument. A member's super is the superclass of the first bridged class on
   self's chain, not of self's class, which for a subclass of a bridged class (or KVO's) would be the bridged class
   itself, and loop. */
enum { BRIDGED_MAX = 256 };
Class __recaulk_objc_axb_bridged[BRIDGED_MAX];

static inline __attribute__((always_inline)) Class floorOf(NSObject *self) {
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c))
        for (int i = 0; i < BRIDGED_MAX && __recaulk_objc_axb_bridged[i]; i++)
            if (__recaulk_objc_axb_bridged[i] == c) return class_getSuperclass(c);
    return Nil;
}

/* Reentry: Recaulk's own NSView and NSCell setter groups (accessibility-common.m) give every view and cell 10.10
   getters that read 10.9's attribute API, so a bridged class without a getter of its own would ask the bridge, which
   asks the getter, which asks the bridge. A member already answering the same question for the same element answers
   it from 10.9 instead. The questions in progress live in the thread's dictionary, never in this image, so no member
   stores to a global. */
static NSString *const askingKey = @"recaulk.accessibility-bridge.asking";

static inline __attribute__((always_inline)) NSString *questionOf(NSObject *self, NSString *question) {
    return [NSString stringWithFormat:@"%p %@", (void *)self, question];
}
static inline __attribute__((always_inline)) BOOL enter(NSObject *self, NSString *question) {
    NSMutableDictionary *perThread = [[NSThread currentThread] threadDictionary];
    NSMutableSet *asking = [perThread objectForKey:askingKey];
    if (!asking) {
        asking = [NSMutableSet set];
        [perThread setObject:asking forKey:askingKey];
    }
    NSString *q = questionOf(self, question);
    if ([asking containsObject:q]) return NO;
    [asking addObject:q];
    return YES;
}
static inline __attribute__((always_inline)) void leave(NSObject *self, NSString *question) {
    NSMutableDictionary *perThread = [[NSThread currentThread] threadDictionary];
    NSMutableSet *asking = [perThread objectForKey:askingKey];
    [asking removeObject:questionOf(self, question)];
}

static NSString *const namesQuestion = @"recaulk:attribute-names", *const parameterizedQuestion = @"recaulk:parameterized",
    *const actionsQuestion = @"recaulk:actions", *const ignoredQuestion = @"recaulk:ignored";

#define SUPER(self) struct objc_super up = { (self), floorOf(self) }

/* spec: iterm's voiceover-3.0.15.tsv -- an attribute is listed when self implements its getter, whatever the getter
   answers now. platform: 10.9's NSView, NSCell and NSObject have none of these getters, so responding is implementing,
   except for the five Recaulk's NSView and NSCell groups add to every view and cell (accessibility-view.m,
   accessibility-cell.m): those list only when they answer.
   spec: Drydock's own-absent bridge (drydock, 2026-11-25) -- unrolled, each respondsToSelector: naming the literal
   selector of the send it guards; a selector loaded from a table is computed, and its guard would not count. */
#define GROUP_GETTER(getter) \
    (sel_isEqual(@selector(getter), @selector(accessibilityLabel)) || \
     sel_isEqual(@selector(getter), @selector(accessibilityRole)) || \
     sel_isEqual(@selector(getter), @selector(accessibilityChildren)) || \
     sel_isEqual(@selector(getter), @selector(accessibilitySelectedTextRange)) || \
     sel_isEqual(@selector(getter), @selector(accessibilityFrame)))
#define LISTED(constant, getter) \
    if (![names containsObject:constant] && [self respondsToSelector:@selector(getter)] && \
        (!GROUP_GETTER(getter) || answer(self, constant))) \
        [names addObject:constant];

NSArray *__recaulk_objc_axb_attribute_names(NSObject *self, SEL _cmd) {
    SUPER(self);
    if (!up.super_class) return nil;
    NSArray *inherited = ((NSArray *(*)(struct objc_super *, SEL))objc_msgSendSuper)(&up, @selector(accessibilityAttributeNames));
    if (!enter(self, namesQuestion)) return inherited;
    NSMutableArray *names = [NSMutableArray arrayWithArray:inherited ? inherited : [NSArray array]];
    MAPPED(LISTED, LISTED, LISTED, LISTED)
    LISTED(NSAccessibilityPositionAttribute, accessibilityFrame)
    LISTED(NSAccessibilitySizeAttribute, accessibilityFrame)
    leave(self, namesQuestion);
    (void)_cmd;
    return names;
}

id __recaulk_objc_axb_attribute_value(NSObject *self, SEL _cmd, NSString *attribute) {
    SUPER(self);
    if (!up.super_class) return nil;
    id mine = nil;
    if (enter(self, attribute)) {
        mine = answer(self, attribute);
        leave(self, attribute);
    }
    (void)_cmd;
    if (mine) return mine;
    return ((id (*)(struct objc_super *, SEL, NSString *))objc_msgSendSuper)(&up, @selector(accessibilityAttributeValue:),
                                                                            attribute);
}

BOOL __recaulk_objc_axb_is_attribute_settable(NSObject *self, SEL _cmd, NSString *attribute) {
    SUPER(self);
    (void)_cmd;
    if (!up.super_class) return NO;
    if (settable(self, attribute)) return YES;
    /* platform: 10.9's NSView and NSCell throw for an attribute they don't implement, so one only this class's getter
       answers is read-only here rather than asked of them */
    if (enter(self, attribute)) {
        id mine = answer(self, attribute);
        leave(self, attribute);
        if (mine) return NO;
    }
    return ((BOOL (*)(struct objc_super *, SEL, NSString *))objc_msgSendSuper)(&up, @selector(accessibilityIsAttributeSettable:),
                                                                              attribute);
}

void __recaulk_objc_axb_set_value(NSObject *self, SEL _cmd, id value, NSString *attribute) {
    SUPER(self);
    (void)_cmd;
    if (!up.super_class) return;
    NSString *a = attribute;
    /* spec: tests/objc-source-receipt.sh -- typed views of the value, so no send has a receiver of type id */
    NSNumber *flag = [value isKindOfClass:[NSNumber class]] ? value : nil;
    NSValue *boxed = [value isKindOfClass:[NSValue class]] ? value : nil;
    if ([a isEqualToString:NSAccessibilityValueAttribute] && [self respondsToSelector:@selector(setAccessibilityValue:)])
        [self setAccessibilityValue:value];
    else if ([a isEqualToString:NSAccessibilityFocusedAttribute] && [self respondsToSelector:@selector(setAccessibilityFocused:)])
        [self setAccessibilityFocused:[flag boolValue]];
    else if ([a isEqualToString:NSAccessibilitySelectedAttribute] && [self respondsToSelector:@selector(setAccessibilitySelected:)])
        [self setAccessibilitySelected:[flag boolValue]];
    else if ([a isEqualToString:NSAccessibilityExpandedAttribute] && [self respondsToSelector:@selector(setAccessibilityExpanded:)])
        [self setAccessibilityExpanded:[flag boolValue]];
    else if ([a isEqualToString:NSAccessibilitySelectedTextAttribute] &&
             [self respondsToSelector:@selector(setAccessibilitySelectedText:)])
        [self setAccessibilitySelectedText:value];
    else if ([a isEqualToString:NSAccessibilitySelectedTextRangesAttribute] &&
             [self respondsToSelector:@selector(setAccessibilitySelectedTextRanges:)])
        [self setAccessibilitySelectedTextRanges:value];
    else if ([a isEqualToString:NSAccessibilityVisibleCharacterRangeAttribute] &&
             [self respondsToSelector:@selector(setAccessibilityVisibleCharacterRange:)] && boxed)
        [self setAccessibilityVisibleCharacterRange:[boxed rangeValue]];
    else
        ((void (*)(struct objc_super *, SEL, id, NSString *))objc_msgSendSuper)(
            &up, @selector(accessibilitySetValue:forAttribute:), value, attribute);
}

NSArray *__recaulk_objc_axb_parameterized_names(NSObject *self, SEL _cmd) {
    SUPER(self);
    (void)_cmd;
    if (!up.super_class) return nil;
    NSArray *inherited =
        ((NSArray *(*)(struct objc_super *, SEL))objc_msgSendSuper)(&up, @selector(accessibilityParameterizedAttributeNames));
    if (!enter(self, parameterizedQuestion)) return inherited;
    NSMutableArray *names = [NSMutableArray arrayWithArray:inherited ? inherited : [NSArray array]];
#define NAME(constant, getter) \
    if ([self respondsToSelector:@selector(getter)] && ![names containsObject:constant]) [names addObject:constant]
    NAME(NSAccessibilityLineForIndexParameterizedAttribute, accessibilityLineForIndex:);
    NAME(NSAccessibilityRangeForLineParameterizedAttribute, accessibilityRangeForLine:);
    NAME(NSAccessibilityStringForRangeParameterizedAttribute, accessibilityStringForRange:);
    NAME(NSAccessibilityRangeForPositionParameterizedAttribute, accessibilityRangeForPosition:);
    NAME(NSAccessibilityRangeForIndexParameterizedAttribute, accessibilityRangeForIndex:);
    NAME(NSAccessibilityBoundsForRangeParameterizedAttribute, accessibilityFrameForRange:);
    NAME(NSAccessibilityRTFForRangeParameterizedAttribute, accessibilityRTFForRange:);
    NAME(NSAccessibilityStyleRangeForIndexParameterizedAttribute, accessibilityStyleRangeForIndex:);
    NAME(NSAccessibilityAttributedStringForRangeParameterizedAttribute, accessibilityAttributedStringForRange:);
#undef NAME
    leave(self, parameterizedQuestion);
    return names;
}

id __recaulk_objc_axb_parameterized_value(NSObject *self, SEL _cmd, NSString *attribute, id parameter) {
    SUPER(self);
    (void)_cmd;
    if (!up.super_class) return nil;
    id mine = parameterized(self, attribute, parameter);
    if (mine) return mine;
    return ((id (*)(struct objc_super *, SEL, NSString *, id))objc_msgSendSuper)(
        &up, @selector(accessibilityAttributeValue:forParameter:), attribute, parameter);
}

NSArray *__recaulk_objc_axb_action_names(NSObject *self, SEL _cmd) {
    SUPER(self);
    (void)_cmd;
    if (!up.super_class) return nil;
    NSArray *inherited = ((NSArray *(*)(struct objc_super *, SEL))objc_msgSendSuper)(&up, @selector(accessibilityActionNames));
    if (!enter(self, actionsQuestion)) return inherited;
    NSMutableArray *names = [NSMutableArray arrayWithArray:inherited ? inherited : [NSArray array]];
    NSArray *all = [NSArray arrayWithObjects:NSAccessibilityPressAction, NSAccessibilityCancelAction,
        NSAccessibilityConfirmAction, NSAccessibilityDecrementAction, NSAccessibilityDeleteAction,
        NSAccessibilityIncrementAction, NSAccessibilityPickAction, NSAccessibilityRaiseAction,
        NSAccessibilityShowAlternateUIAction, NSAccessibilityShowDefaultUIAction, NSAccessibilityShowMenuAction, nil];
    for (NSString *a in all) {
        BOOL known;
        action(self, a, NO, &known);
        if (known && ![names containsObject:a]) [names addObject:a];
    }
    leave(self, actionsQuestion);
    return names;
}

NSString *__recaulk_objc_axb_action_description(NSObject *self, SEL _cmd, NSString *name) {
    SUPER(self);
    (void)_cmd;
    if (!up.super_class) return nil;
    BOOL known = NO;
    action(self, name, NO, &known);
    if (known) return NSAccessibilityActionDescription(name);
    return ((NSString *(*)(struct objc_super *, SEL, NSString *))objc_msgSendSuper)(
        &up, @selector(accessibilityActionDescription:), name);
}

void __recaulk_objc_axb_perform_action(NSObject *self, SEL _cmd, NSString *name) {
    SUPER(self);
    (void)_cmd;
    if (!up.super_class) return;
    BOOL known = NO;
    action(self, name, YES, &known);
    if (known) return;
    ((void (*)(struct objc_super *, SEL, NSString *))objc_msgSendSuper)(&up, @selector(accessibilityPerformAction:), name);
}

/* platform: 10.9 AppKit ignores a plain NSView subclass (and a control, whose cell it exposes instead). A class
   that says it is an element (10.10's isAccessibilityElement) is not ignored; nor, as 10.10's NSView treats an
   element that answers a role, is one whose role getter answers a role other than unknown. Otherwise 10.9 decides. */
BOOL __recaulk_objc_axb_is_ignored(NSObject *self, SEL _cmd) {
    SUPER(self);
    (void)_cmd;
    if (!up.super_class) return YES;
    if (enter(self, ignoredQuestion)) {
        int decided = -1;
        if ([self respondsToSelector:@selector(isAccessibilityElement)]) {
            decided = ![self isAccessibilityElement];
        } else if ([self respondsToSelector:@selector(accessibilityRole)]) {
            NSString *role = [self accessibilityRole];
            if (role && ![role isEqualToString:NSAccessibilityUnknownRole]) decided = NO;
        }
        leave(self, ignoredQuestion);
        if (decided >= 0) return (BOOL)decided;
    }
    return ((BOOL (*)(struct objc_super *, SEL))objc_msgSendSuper)(&up, @selector(accessibilityIsIgnored));
}

/* spec: Drydock's own-absent bridge (drydock, 2026-11-25) -- every helper an IMP calls is inlined, so its getter and super
   sends are the IMP's own.
   spec: README.md "Objective-C methods", the accessibility bridge -- the root records the class in its one table symbol, then adds each member
   with a literal selector, implementation and the floor's 10.9 type, and nothing else: no lookup, no replace. */
__attribute__((noinline)) void recaulk_accessibility_bridge(Class cls) {
    if (!cls) return;
    /* The root's one store: the class into the first empty slot, unless it is already there or the table is full; the
       members are added on every path, whatever the table holds. Scalar, since drydock's executor has no SSE. */
#pragma clang loop vectorize(disable) interleave(disable)
    for (int i = 0; i < BRIDGED_MAX; i++) {
        if (__recaulk_objc_axb_bridged[i] == cls) break;
        if (!__recaulk_objc_axb_bridged[i]) {
            __recaulk_objc_axb_bridged[i] = cls;
            break;
        }
    }
    class_addMethod(cls, sel_registerName("accessibilityAttributeNames"), (IMP)__recaulk_objc_axb_attribute_names,
                    "@16@0:8");
    class_addMethod(cls, sel_registerName("accessibilityAttributeValue:"), (IMP)__recaulk_objc_axb_attribute_value,
                    "@24@0:8@16");
    class_addMethod(cls, sel_registerName("accessibilityIsAttributeSettable:"),
                    (IMP)__recaulk_objc_axb_is_attribute_settable, "c24@0:8@16");
    class_addMethod(cls, sel_registerName("accessibilitySetValue:forAttribute:"), (IMP)__recaulk_objc_axb_set_value,
                    "v32@0:8@16@24");
    class_addMethod(cls, sel_registerName("accessibilityParameterizedAttributeNames"),
                    (IMP)__recaulk_objc_axb_parameterized_names, "@16@0:8");
    class_addMethod(cls, sel_registerName("accessibilityAttributeValue:forParameter:"),
                    (IMP)__recaulk_objc_axb_parameterized_value, "@32@0:8@16@24");
    class_addMethod(cls, sel_registerName("accessibilityActionNames"), (IMP)__recaulk_objc_axb_action_names, "@16@0:8");
    class_addMethod(cls, sel_registerName("accessibilityActionDescription:"), (IMP)__recaulk_objc_axb_action_description,
                    "@24@0:8@16");
    class_addMethod(cls, sel_registerName("accessibilityPerformAction:"), (IMP)__recaulk_objc_axb_perform_action,
                    "v24@0:8@16");
    class_addMethod(cls, sel_registerName("accessibilityIsIgnored"), (IMP)__recaulk_objc_axb_is_ignored, "c16@0:8");
    /* Not a tail call: Drydock 0.7.0's executor loses the failed-add path of a class_addMethod reached by a jump
       (regexec.c do_call: the fork keeps the jump's fall-through address), so the last add returns here. */
    __asm__ volatile("" ::: "memory");
}
