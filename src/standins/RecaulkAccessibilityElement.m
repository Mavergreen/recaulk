/* RecaulkAccessibilityElement: 10.10's NSAccessibilityElement for 10.9, which lacks it.
 *
 * An app written for 10.10 subclasses NSAccessibilityElement for UI with no view of its own (iTerm2's tabs). On 10.9
 * that superclass is missing, so the runtime never realizes the subclass. libRecaulkAppKit.dylib exports this class as
 * NSAccessibilityElement's class and metaclass (build/standins.txt, build/build-standins.sh); an app binding them flat
 * and weak, with AppKit loaded first, gets AppKit's class where AppKit has one and this one on 10.9. Its runtime name
 * stays its own, so it never collides with AppKit's.
 *
 * It keeps the 10.10 API (the factory, accessibilityAddChildElement:, accessibilityFrameInParentSpace and the
 * NSAccessibility protocol's properties it stores) and answers 10.9's attribute API, which is all 10.9's VoiceOver
 * asks, from the 10.10 getters: a subclass's override of a getter is what 10.9 hears. Drydock's provided-class rule:
 * only these methods, its ivars and the compiler's .cxx_destruct; no +load, no +initialize, no -init. */
#import <AppKit/AppKit.h>
#import "accessibility-map.h"

#if !__has_feature(objc_arc)
#error RecaulkAccessibilityElement relies on ARC for its ivars (Drydock's rule: no -dealloc of its own)
#endif

@interface RecaulkAccessibilityElement : NSObject
@end

@implementation RecaulkAccessibilityElement {
    NSString *_role, *_subrole, *_roleDescription, *_label, *_title, *_help, *_identifier;
    id _value;
    /* platform: 10.9 refuses a weak reference to some AppKit objects (NSWindow, NSTextView), so the parent is not
       retained and not zeroed, as NSAccessibilityElement.h asks its vendor to keep its elements' parents alive */
    __unsafe_unretained id _parent;
    NSArray *_children;
    NSRect _frame, _frameInParentSpace;
    BOOL _inParentSpace;
    /* inverted so that the zeroed object is 10.10's default: enabled, and an element */
    BOOL _disabled, _notElement, _focused, _selected;
}

/* spec: MacOSX10.10.sdk NSAccessibilityElement.h -- the factory, with frame in screen coordinates */
+ (id)accessibilityElementWithRole:(NSString *)role frame:(NSRect)frame label:(NSString *)label parent:(id)parent {
    RecaulkAccessibilityElement *e = [[self alloc] init];
    e->_role = [role copy];
    e->_frame = frame;
    e->_label = [label copy];
    e->_parent = parent;
    return e;
}

- (void)accessibilityAddChildElement:(RecaulkAccessibilityElement *)childElement {
    if (!childElement) return;
    _children = _children ? [_children arrayByAddingObject:childElement] : [NSArray arrayWithObject:childElement];
    if ([childElement isKindOfClass:[RecaulkAccessibilityElement class]]) childElement->_parent = self;
}

- (NSRect)accessibilityFrameInParentSpace { return _frameInParentSpace; }
- (void)setAccessibilityFrameInParentSpace:(NSRect)frame { _frameInParentSpace = frame; _inParentSpace = YES; }

/* platform: 10.10's element in parent space is offset by its parent's screen frame */
- (NSRect)accessibilityFrame {
    if (!_inParentSpace) return _frame;
    NSRect up = NSZeroRect;
    if ([_parent respondsToSelector:@selector(accessibilityFrame)]) {
        up = [_parent accessibilityFrame];
    } else if ([_parent respondsToSelector:@selector(accessibilityAttributeValue:)]) {
        NSValue *at = [_parent accessibilityAttributeValue:NSAccessibilityPositionAttribute];
        if ([at isKindOfClass:[NSValue class]]) up.origin = [at pointValue];
    }
    return NSOffsetRect(_frameInParentSpace, up.origin.x, up.origin.y);
}
- (void)setAccessibilityFrame:(NSRect)frame { _frame = frame; _inParentSpace = NO; }

- (NSString *)accessibilityRole { return _role; }
- (void)setAccessibilityRole:(NSString *)role { _role = [role copy]; }
- (NSString *)accessibilitySubrole { return _subrole; }
- (void)setAccessibilitySubrole:(NSString *)subrole { _subrole = [subrole copy]; }
- (NSString *)accessibilityRoleDescription {
    return _roleDescription ? _roleDescription : _role ? NSAccessibilityRoleDescription(_role, _subrole) : nil;
}
- (void)setAccessibilityRoleDescription:(NSString *)d { _roleDescription = [d copy]; }
- (NSString *)accessibilityLabel { return _label; }
- (void)setAccessibilityLabel:(NSString *)label { _label = [label copy]; }
- (NSString *)accessibilityTitle { return _title; }
- (void)setAccessibilityTitle:(NSString *)title { _title = [title copy]; }
- (NSString *)accessibilityHelp { return _help; }
- (void)setAccessibilityHelp:(NSString *)help { _help = [help copy]; }
- (NSString *)accessibilityIdentifier { return _identifier; }
- (void)setAccessibilityIdentifier:(NSString *)identifier { _identifier = [identifier copy]; }
- (id)accessibilityValue { return _value; }
- (void)setAccessibilityValue:(id)value { _value = value; }
- (id)accessibilityParent { return _parent; }
- (void)setAccessibilityParent:(id)parent { _parent = parent; }
- (NSArray *)accessibilityChildren { return _children; }
- (void)setAccessibilityChildren:(NSArray *)children { _children = [children copy]; }
- (BOOL)isAccessibilityEnabled { return !_disabled; }
- (void)setAccessibilityEnabled:(BOOL)enabled { _disabled = !enabled; }
- (BOOL)isAccessibilityFocused { return _focused; }
- (void)setAccessibilityFocused:(BOOL)focused { _focused = focused; }
- (BOOL)isAccessibilitySelected { return _selected; }
- (void)setAccessibilitySelected:(BOOL)selected { _selected = selected; }
- (BOOL)isAccessibilityElement { return !_notElement; }
- (void)setAccessibilityElement:(BOOL)element { _notElement = !element; }

/* platform: an element's window is its parent's, which on 10.9 is a view answering the attribute API */
- (id)accessibilityWindow {
    return [_parent respondsToSelector:@selector(accessibilityAttributeValue:)]
        ? [_parent accessibilityAttributeValue:NSAccessibilityWindowAttribute] : nil;
}
- (id)accessibilityTopLevelUIElement {
    return [_parent respondsToSelector:@selector(accessibilityAttributeValue:)]
        ? [_parent accessibilityAttributeValue:NSAccessibilityTopLevelUIElementAttribute] : nil;
}

/* 10.9's attribute API, from the getters above or a subclass's (accessibility-map.h, shared with the bridge) */
- (NSArray *)accessibilityAttributeNames {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *a in mappedAttributes())
        if (answer(self, a)) [names addObject:a];
    return names;
}
- (id)accessibilityAttributeValue:(NSString *)attribute { return answer(self, attribute); }
- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute { return settable(self, attribute); }
- (void)accessibilitySetValue:(id)value forAttribute:(NSString *)attribute {
    /* spec: tests/objc-source-receipt.sh -- typed views of the value, so no send has a receiver of type id */
    NSNumber *flag = [value isKindOfClass:[NSNumber class]] ? value : nil;
    if ([attribute isEqualToString:NSAccessibilityValueAttribute]) [self setAccessibilityValue:value];
    else if ([attribute isEqualToString:NSAccessibilityFocusedAttribute]) [self setAccessibilityFocused:[flag boolValue]];
    else if ([attribute isEqualToString:NSAccessibilitySelectedAttribute]) [self setAccessibilitySelected:[flag boolValue]];
}

- (NSArray *)accessibilityParameterizedAttributeNames {
    /* each 10.9 parameterized attribute after the 10.10 getter parameterized() answers it from */
    static const struct { NSString *const *name; const char *getter; } table[] = {
        { &NSAccessibilityLineForIndexParameterizedAttribute, "accessibilityLineForIndex:" },
        { &NSAccessibilityRangeForLineParameterizedAttribute, "accessibilityRangeForLine:" },
        { &NSAccessibilityStringForRangeParameterizedAttribute, "accessibilityStringForRange:" },
        { &NSAccessibilityRangeForPositionParameterizedAttribute, "accessibilityRangeForPosition:" },
        { &NSAccessibilityRangeForIndexParameterizedAttribute, "accessibilityRangeForIndex:" },
        { &NSAccessibilityBoundsForRangeParameterizedAttribute, "accessibilityFrameForRange:" },
        { &NSAccessibilityRTFForRangeParameterizedAttribute, "accessibilityRTFForRange:" },
        { &NSAccessibilityStyleRangeForIndexParameterizedAttribute, "accessibilityStyleRangeForIndex:" },
        { &NSAccessibilityAttributedStringForRangeParameterizedAttribute, "accessibilityAttributedStringForRange:" },
    };
    NSMutableArray *names = [NSMutableArray array];
    for (size_t i = 0; i < sizeof table / sizeof table[0]; i++)
        if ([self respondsToSelector:sel_registerName(table[i].getter)]) [names addObject:*table[i].name];
    return names;
}
- (id)accessibilityAttributeValue:(NSString *)attribute forParameter:(id)parameter {
    return parameterized(self, attribute, parameter);
}

- (NSArray *)accessibilityActionNames {
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
- (NSString *)accessibilityActionDescription:(NSString *)name {
    BOOL known = NO;
    action(self, name, NO, &known);
    return known ? NSAccessibilityActionDescription(name) : nil;
}
- (void)accessibilityPerformAction:(NSString *)name {
    BOOL known = NO;
    action(self, name, YES, &known);
}

- (BOOL)accessibilityIsIgnored { return ![self isAccessibilityElement]; }
- (id)accessibilityHitTest:(NSPoint)point { (void)point; return self; }
- (id)accessibilityFocusedUIElement { return self; }

@end
