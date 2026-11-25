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

/* spec: src/include/recaulk/accessibility.h -- the public declaration, repeated here because the source receipt reads
   only this directory's inputs; tests/objc-accessibility-bridge.sh links a program compiled against that header */
void recaulk_accessibility_bridge(Class cls);

/* platform: 10.10's NSAccessibility protocol (MacOSX10.10.sdk and later, NSAccessibilityProtocols.h), as it declares
   each getter, setter and action this bridge maps; a bridged class answers only those it implements, so every send
   below is under respondsToSelector: of its own selector */
@interface NSObject (RecaulkAccessibilityBridge)
- (BOOL)isAccessibilityElement;
- (NSString *)accessibilityRole;
- (NSString *)accessibilitySubrole;
- (NSString *)accessibilityRoleDescription;
- (NSString *)accessibilityLabel;
- (NSString *)accessibilityTitle;
- (NSString *)accessibilityHelp;
- (id)accessibilityValue;
- (void)setAccessibilityValue:(id)value;
- (NSString *)accessibilityValueDescription;
- (NSString *)accessibilityPlaceholderValue;
- (NSString *)accessibilityIdentifier;
- (NSString *)accessibilityDocument;
- (NSString *)accessibilityFilename;
- (NSURL *)accessibilityURL;
- (id)accessibilityParent;
- (id)accessibilityWindow;
- (id)accessibilityTopLevelUIElement;
- (NSArray *)accessibilityChildren;
- (NSArray *)accessibilityVisibleChildren;
- (NSArray *)accessibilitySelectedChildren;
- (NSArray *)accessibilityContents;
- (NSArray *)accessibilityTabs;
- (NSArray *)accessibilityRows;
- (NSArray *)accessibilityColumns;
- (NSRect)accessibilityFrame;
- (BOOL)isAccessibilityEnabled;
- (BOOL)isAccessibilityFocused;
- (void)setAccessibilityFocused:(BOOL)focused;
- (BOOL)isAccessibilitySelected;
- (void)setAccessibilitySelected:(BOOL)selected;
- (BOOL)isAccessibilityExpanded;
- (void)setAccessibilityExpanded:(BOOL)expanded;
- (BOOL)isAccessibilityEdited;
- (NSInteger)accessibilityIndex;
- (NSInteger)accessibilityNumberOfCharacters;
- (NSInteger)accessibilityInsertionPointLineNumber;
- (NSString *)accessibilitySelectedText;
- (void)setAccessibilitySelectedText:(NSString *)text;
- (NSRange)accessibilitySelectedTextRange;
- (NSArray *)accessibilitySelectedTextRanges;
- (void)setAccessibilitySelectedTextRanges:(NSArray *)ranges;
- (NSRange)accessibilityVisibleCharacterRange;
- (void)setAccessibilityVisibleCharacterRange:(NSRange)range;
- (NSInteger)accessibilityLineForIndex:(NSInteger)index;
- (NSRange)accessibilityRangeForLine:(NSInteger)line;
- (NSString *)accessibilityStringForRange:(NSRange)range;
- (NSRange)accessibilityRangeForPosition:(NSPoint)point;
- (NSRange)accessibilityRangeForIndex:(NSInteger)index;
- (NSRect)accessibilityFrameForRange:(NSRange)range;
- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range;
- (NSData *)accessibilityRTFForRange:(NSRange)range;
- (NSRange)accessibilityStyleRangeForIndex:(NSInteger)index;
- (BOOL)accessibilityPerformCancel;
- (BOOL)accessibilityPerformConfirm;
- (BOOL)accessibilityPerformDecrement;
- (BOOL)accessibilityPerformDelete;
- (BOOL)accessibilityPerformIncrement;
- (BOOL)accessibilityPerformPick;
- (BOOL)accessibilityPerformPress;
- (BOOL)accessibilityPerformRaise;
- (BOOL)accessibilityPerformShowAlternateUI;
- (BOOL)accessibilityPerformShowDefaultUI;
- (BOOL)accessibilityPerformShowMenu;
@end

/* The classes the app has bridged: one data symbol, which only the root writes (Drydock's group declaration names it).
   A member's super is the superclass of the first bridged class on self's chain, not of self's class, which for a
   subclass of a bridged class (or KVO's) would be the bridged class itself, and loop. A reserved slot not yet filled
   is Nil, which no class matches. */
enum { BRIDGED_MAX = 256 };
struct __recaulk_objc_axb_table { volatile int count; Class classes[BRIDGED_MAX]; };
struct __recaulk_objc_axb_table __recaulk_objc_axb_bridged = { 0, { Nil } };

static Class floorOf(NSObject *self) {
    int n = __recaulk_objc_axb_bridged.count;
    if (n > BRIDGED_MAX) n = BRIDGED_MAX;
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c))
        for (int i = 0; i < n; i++)
            if (__recaulk_objc_axb_bridged.classes[i] == c) return class_getSuperclass(c);
    return Nil;
}

/* Reentry: Recaulk's own NSView and NSCell setter groups (accessibility-common.m) give every view and cell 10.10
   getters that read 10.9's attribute API, so a bridged class without a getter of its own would ask the bridge, which
   asks the getter, which asks the bridge. A member already answering the same question for the same element answers
   it from 10.9 instead. */
enum { DEPTH_MAX = 32 };
struct asking { NSObject *element; NSString *question; };
static __thread struct asking asked[DEPTH_MAX];
static __thread int depth;

static BOOL enter(NSObject *self, NSString *question) {
    if (depth >= DEPTH_MAX) return NO;
    for (int i = 0; i < depth; i++)
        if (asked[i].element == self && [asked[i].question isEqualToString:question]) return NO;
    asked[depth].element = self;
    asked[depth].question = question;
    depth++;
    return YES;
}
static void leave(void) { depth--; }

static NSString *const namesQuestion = @"recaulk:attribute-names", *const parameterizedQuestion = @"recaulk:parameterized",
    *const actionsQuestion = @"recaulk:actions", *const ignoredQuestion = @"recaulk:ignored";

#define SUPER(self) struct objc_super up = { (self), floorOf(self) }

/* The 10.10 getter's answer to a 10.9 attribute, boxed as 10.9 boxes it; nil where self has no getter for it or the
   getter answers nil (or NSNotFound for a range). */
static id answer(NSObject *self, NSString *a) {
#define OBJECT(constant, getter) \
    if ([a isEqualToString:constant]) return [self respondsToSelector:@selector(getter)] ? [self getter] : nil
#define FLAG(constant, getter) \
    if ([a isEqualToString:constant]) \
        return [self respondsToSelector:@selector(getter)] ? [NSNumber numberWithBool:[self getter]] : nil
#define INTEGER(constant, getter) \
    if ([a isEqualToString:constant]) \
        return [self respondsToSelector:@selector(getter)] ? [NSNumber numberWithInteger:[self getter]] : nil
#define RANGE(constant, getter) \
    if ([a isEqualToString:constant]) { \
        if (![self respondsToSelector:@selector(getter)]) return nil; \
        NSRange r = [self getter]; \
        return r.location == NSNotFound ? nil : [NSValue valueWithRange:r]; \
    }
    OBJECT(NSAccessibilityRoleAttribute, accessibilityRole);
    OBJECT(NSAccessibilitySubroleAttribute, accessibilitySubrole);
    OBJECT(NSAccessibilityRoleDescriptionAttribute, accessibilityRoleDescription);
    OBJECT(NSAccessibilityDescriptionAttribute, accessibilityLabel);
    OBJECT(NSAccessibilityTitleAttribute, accessibilityTitle);
    OBJECT(NSAccessibilityHelpAttribute, accessibilityHelp);
    OBJECT(NSAccessibilityValueAttribute, accessibilityValue);
    OBJECT(NSAccessibilityValueDescriptionAttribute, accessibilityValueDescription);
    OBJECT(NSAccessibilityPlaceholderValueAttribute, accessibilityPlaceholderValue);
    OBJECT(NSAccessibilityIdentifierAttribute, accessibilityIdentifier);
    OBJECT(NSAccessibilityDocumentAttribute, accessibilityDocument);
    OBJECT(NSAccessibilityFilenameAttribute, accessibilityFilename);
    OBJECT(NSAccessibilityURLAttribute, accessibilityURL);
    OBJECT(NSAccessibilityParentAttribute, accessibilityParent);
    OBJECT(NSAccessibilityWindowAttribute, accessibilityWindow);
    OBJECT(NSAccessibilityTopLevelUIElementAttribute, accessibilityTopLevelUIElement);
    OBJECT(NSAccessibilityChildrenAttribute, accessibilityChildren);
    OBJECT(NSAccessibilityVisibleChildrenAttribute, accessibilityVisibleChildren);
    OBJECT(NSAccessibilitySelectedChildrenAttribute, accessibilitySelectedChildren);
    OBJECT(NSAccessibilityContentsAttribute, accessibilityContents);
    OBJECT(NSAccessibilityTabsAttribute, accessibilityTabs);
    OBJECT(NSAccessibilityRowsAttribute, accessibilityRows);
    OBJECT(NSAccessibilityColumnsAttribute, accessibilityColumns);
    OBJECT(NSAccessibilitySelectedTextAttribute, accessibilitySelectedText);
    OBJECT(NSAccessibilitySelectedTextRangesAttribute, accessibilitySelectedTextRanges);
    FLAG(NSAccessibilityEnabledAttribute, isAccessibilityEnabled);
    FLAG(NSAccessibilityFocusedAttribute, isAccessibilityFocused);
    FLAG(NSAccessibilitySelectedAttribute, isAccessibilitySelected);
    FLAG(NSAccessibilityExpandedAttribute, isAccessibilityExpanded);
    FLAG(NSAccessibilityEditedAttribute, isAccessibilityEdited);
    INTEGER(NSAccessibilityIndexAttribute, accessibilityIndex);
    INTEGER(NSAccessibilityNumberOfCharactersAttribute, accessibilityNumberOfCharacters);
    INTEGER(NSAccessibilityInsertionPointLineNumberAttribute, accessibilityInsertionPointLineNumber);
    RANGE(NSAccessibilitySelectedTextRangeAttribute, accessibilitySelectedTextRange);
    RANGE(NSAccessibilityVisibleCharacterRangeAttribute, accessibilityVisibleCharacterRange);
    /* platform: 10.9's AXPosition is the element's lower-left corner in screen coordinates, as 10.10's frame origin is */
    if ([a isEqualToString:NSAccessibilityPositionAttribute] || [a isEqualToString:NSAccessibilitySizeAttribute]) {
        if (![self respondsToSelector:@selector(accessibilityFrame)]) return nil;
        NSRect frame = [self accessibilityFrame];
        if ([a isEqualToString:NSAccessibilityPositionAttribute]) return [NSValue valueWithPoint:frame.origin];
        return [NSValue valueWithSize:frame.size];
    }
#undef OBJECT
#undef FLAG
#undef INTEGER
#undef RANGE
    return nil;
}

/* Every 10.9 attribute answer() maps, in the order 10.9 lists its own. */
static NSArray *mappedAttributes(void) {
    return [NSArray arrayWithObjects:NSAccessibilityRoleAttribute, NSAccessibilitySubroleAttribute,
        NSAccessibilityRoleDescriptionAttribute, NSAccessibilityDescriptionAttribute, NSAccessibilityTitleAttribute,
        NSAccessibilityHelpAttribute, NSAccessibilityValueAttribute, NSAccessibilityValueDescriptionAttribute,
        NSAccessibilityPlaceholderValueAttribute, NSAccessibilityIdentifierAttribute, NSAccessibilityDocumentAttribute,
        NSAccessibilityFilenameAttribute, NSAccessibilityURLAttribute, NSAccessibilityParentAttribute,
        NSAccessibilityWindowAttribute, NSAccessibilityTopLevelUIElementAttribute, NSAccessibilityChildrenAttribute,
        NSAccessibilityVisibleChildrenAttribute, NSAccessibilitySelectedChildrenAttribute,
        NSAccessibilityContentsAttribute, NSAccessibilityTabsAttribute, NSAccessibilityRowsAttribute,
        NSAccessibilityColumnsAttribute, NSAccessibilitySelectedTextAttribute, NSAccessibilitySelectedTextRangesAttribute,
        NSAccessibilityEnabledAttribute, NSAccessibilityFocusedAttribute, NSAccessibilitySelectedAttribute,
        NSAccessibilityExpandedAttribute, NSAccessibilityEditedAttribute, NSAccessibilityIndexAttribute,
        NSAccessibilityNumberOfCharactersAttribute, NSAccessibilityInsertionPointLineNumberAttribute,
        NSAccessibilitySelectedTextRangeAttribute, NSAccessibilityVisibleCharacterRangeAttribute,
        NSAccessibilityPositionAttribute, NSAccessibilitySizeAttribute, nil];
}

NSArray *__recaulk_objc_axb_attribute_names(NSObject *self, SEL _cmd) {
    SUPER(self);
    if (!up.super_class) return nil;
    NSArray *inherited = ((NSArray *(*)(struct objc_super *, SEL))objc_msgSendSuper)(&up, @selector(accessibilityAttributeNames));
    if (!enter(self, namesQuestion)) return inherited;
    NSMutableArray *names = [NSMutableArray arrayWithArray:inherited ? inherited : [NSArray array]];
    for (NSString *a in mappedAttributes())
        if (![names containsObject:a] && answer(self, a)) [names addObject:a];
    leave();
    (void)_cmd;
    return names;
}

id __recaulk_objc_axb_attribute_value(NSObject *self, SEL _cmd, NSString *attribute) {
    SUPER(self);
    if (!up.super_class) return nil;
    id mine = nil;
    if (enter(self, attribute)) {
        mine = answer(self, attribute);
        leave();
    }
    (void)_cmd;
    if (mine) return mine;
    return ((id (*)(struct objc_super *, SEL, NSString *))objc_msgSendSuper)(&up, @selector(accessibilityAttributeValue:),
                                                                            attribute);
}

/* Settable through a 10.10 setter the class implements. Not the label, role, children or selected-text-range setters:
   Recaulk's setter groups give every view and cell those, so responding to them says nothing about this class. */
static BOOL settable(NSObject *self, NSString *a) {
    if ([a isEqualToString:NSAccessibilityValueAttribute]) return [self respondsToSelector:@selector(setAccessibilityValue:)];
    if ([a isEqualToString:NSAccessibilityFocusedAttribute])
        return [self respondsToSelector:@selector(setAccessibilityFocused:)];
    if ([a isEqualToString:NSAccessibilitySelectedAttribute])
        return [self respondsToSelector:@selector(setAccessibilitySelected:)];
    if ([a isEqualToString:NSAccessibilityExpandedAttribute])
        return [self respondsToSelector:@selector(setAccessibilityExpanded:)];
    if ([a isEqualToString:NSAccessibilitySelectedTextAttribute])
        return [self respondsToSelector:@selector(setAccessibilitySelectedText:)];
    if ([a isEqualToString:NSAccessibilitySelectedTextRangesAttribute])
        return [self respondsToSelector:@selector(setAccessibilitySelectedTextRanges:)];
    if ([a isEqualToString:NSAccessibilityVisibleCharacterRangeAttribute])
        return [self respondsToSelector:@selector(setAccessibilityVisibleCharacterRange:)];
    return NO;
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
        leave();
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

/* The 10.10 parameterized getters, each by its 10.9 parameterized attribute: an index or line parameter is an
   NSNumber, a range an NSValue of a range, a position an NSValue of a point. */
static id parameterized(NSObject *self, NSString *a, id p) {
    /* spec: tests/objc-source-receipt.sh -- typed views of the parameter, so no send has a receiver of type id */
    NSNumber *index = [p isKindOfClass:[NSNumber class]] ? p : nil;
    NSValue *value = [p isKindOfClass:[NSValue class]] ? p : nil;
    BOOL number = index != nil, boxed = value != nil;
    if ([a isEqualToString:NSAccessibilityLineForIndexParameterizedAttribute])
        return number && [self respondsToSelector:@selector(accessibilityLineForIndex:)]
            ? [NSNumber numberWithInteger:[self accessibilityLineForIndex:[index integerValue]]] : nil;
    if ([a isEqualToString:NSAccessibilityRangeForLineParameterizedAttribute])
        return number && [self respondsToSelector:@selector(accessibilityRangeForLine:)]
            ? [NSValue valueWithRange:[self accessibilityRangeForLine:[index integerValue]]] : nil;
    if ([a isEqualToString:NSAccessibilityRangeForIndexParameterizedAttribute])
        return number && [self respondsToSelector:@selector(accessibilityRangeForIndex:)]
            ? [NSValue valueWithRange:[self accessibilityRangeForIndex:[index integerValue]]] : nil;
    if ([a isEqualToString:NSAccessibilityStyleRangeForIndexParameterizedAttribute])
        return number && [self respondsToSelector:@selector(accessibilityStyleRangeForIndex:)]
            ? [NSValue valueWithRange:[self accessibilityStyleRangeForIndex:[index integerValue]]] : nil;
    if ([a isEqualToString:NSAccessibilityRangeForPositionParameterizedAttribute])
        return boxed && [self respondsToSelector:@selector(accessibilityRangeForPosition:)]
            ? [NSValue valueWithRange:[self accessibilityRangeForPosition:[value pointValue]]] : nil;
    if ([a isEqualToString:NSAccessibilityStringForRangeParameterizedAttribute])
        return boxed && [self respondsToSelector:@selector(accessibilityStringForRange:)]
            ? [self accessibilityStringForRange:[value rangeValue]] : nil;
    if ([a isEqualToString:NSAccessibilityBoundsForRangeParameterizedAttribute])
        return boxed && [self respondsToSelector:@selector(accessibilityFrameForRange:)]
            ? [NSValue valueWithRect:[self accessibilityFrameForRange:[value rangeValue]]] : nil;
    if ([a isEqualToString:NSAccessibilityAttributedStringForRangeParameterizedAttribute])
        return boxed && [self respondsToSelector:@selector(accessibilityAttributedStringForRange:)]
            ? [self accessibilityAttributedStringForRange:[value rangeValue]] : nil;
    if ([a isEqualToString:NSAccessibilityRTFForRangeParameterizedAttribute])
        return boxed && [self respondsToSelector:@selector(accessibilityRTFForRange:)]
            ? [self accessibilityRTFForRange:[value rangeValue]] : nil;
    return nil;
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
    leave();
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

/* Each 10.9 action with the 10.10 perform method that does it: the action is offered where self implements the
   method. *known says whether self implements it, and the method is called only when call is YES. */
static BOOL action(NSObject *self, NSString *a, BOOL call, BOOL *known) {
#define ACTION(constant, method) \
    if ([a isEqualToString:constant]) { \
        *known = [self respondsToSelector:@selector(method)]; \
        return *known && call ? [self method] : NO; \
    }
    ACTION(NSAccessibilityPressAction, accessibilityPerformPress);
    ACTION(NSAccessibilityCancelAction, accessibilityPerformCancel);
    ACTION(NSAccessibilityConfirmAction, accessibilityPerformConfirm);
    ACTION(NSAccessibilityDecrementAction, accessibilityPerformDecrement);
    ACTION(NSAccessibilityDeleteAction, accessibilityPerformDelete);
    ACTION(NSAccessibilityIncrementAction, accessibilityPerformIncrement);
    ACTION(NSAccessibilityPickAction, accessibilityPerformPick);
    ACTION(NSAccessibilityRaiseAction, accessibilityPerformRaise);
    ACTION(NSAccessibilityShowAlternateUIAction, accessibilityPerformShowAlternateUI);
    ACTION(NSAccessibilityShowDefaultUIAction, accessibilityPerformShowDefaultUI);
    ACTION(NSAccessibilityShowMenuAction, accessibilityPerformShowMenu);
#undef ACTION
    *known = NO;
    return NO;
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
    leave();
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
        leave();
        if (decided >= 0) return (BOOL)decided;
    }
    return ((BOOL (*)(struct objc_super *, SEL))objc_msgSendSuper)(&up, @selector(accessibilityIsIgnored));
}

/* spec: README.md "Objective-C methods", the accessibility bridge -- the root records the class in its one table symbol, then adds each member
   with a literal selector, implementation and the floor's 10.9 type, and nothing else: no lookup, no replace. */
__attribute__((noinline)) void recaulk_accessibility_bridge(Class cls) {
    if (!cls) return;
    int slot = __sync_fetch_and_add(&__recaulk_objc_axb_bridged.count, 1);
    if (slot < BRIDGED_MAX) __recaulk_objc_axb_bridged.classes[slot] = cls;
    __sync_synchronize();
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
