/* The pure mapping between 10.10's NSAccessibility protocol and 10.9's attribute API, shared by the accessibility
 * bridge (accessibility-bridge.m, into an app's own classes) and the NSAccessibilityElement stand-in
 * (src/standins/RecaulkAccessibilityElement.m, a class of Recaulk's). No state and no constructor, and each function
 * is inlined into its caller (Drydock's own-absent bridge counts a helper call as unmodelled), so including it adds
 * no function and changes neither file's members. */
#ifndef RECAULK_ACCESSIBILITY_MAP_H
#define RECAULK_ACCESSIBILITY_MAP_H
#import <AppKit/AppKit.h>

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

/* Each 10.9 attribute the bridge maps, with the 10.10 getter it reads, by how 10.9 boxes the answer. */
#define MAPPED(OBJECT, FLAG, INTEGER, RANGE) \
    OBJECT(NSAccessibilityRoleAttribute, accessibilityRole) \
    OBJECT(NSAccessibilitySubroleAttribute, accessibilitySubrole) \
    OBJECT(NSAccessibilityRoleDescriptionAttribute, accessibilityRoleDescription) \
    OBJECT(NSAccessibilityDescriptionAttribute, accessibilityLabel) \
    OBJECT(NSAccessibilityTitleAttribute, accessibilityTitle) \
    OBJECT(NSAccessibilityHelpAttribute, accessibilityHelp) \
    OBJECT(NSAccessibilityValueAttribute, accessibilityValue) \
    OBJECT(NSAccessibilityValueDescriptionAttribute, accessibilityValueDescription) \
    OBJECT(NSAccessibilityPlaceholderValueAttribute, accessibilityPlaceholderValue) \
    OBJECT(NSAccessibilityIdentifierAttribute, accessibilityIdentifier) \
    OBJECT(NSAccessibilityDocumentAttribute, accessibilityDocument) \
    OBJECT(NSAccessibilityFilenameAttribute, accessibilityFilename) \
    OBJECT(NSAccessibilityURLAttribute, accessibilityURL) \
    OBJECT(NSAccessibilityParentAttribute, accessibilityParent) \
    OBJECT(NSAccessibilityWindowAttribute, accessibilityWindow) \
    OBJECT(NSAccessibilityTopLevelUIElementAttribute, accessibilityTopLevelUIElement) \
    OBJECT(NSAccessibilityChildrenAttribute, accessibilityChildren) \
    OBJECT(NSAccessibilityVisibleChildrenAttribute, accessibilityVisibleChildren) \
    OBJECT(NSAccessibilitySelectedChildrenAttribute, accessibilitySelectedChildren) \
    OBJECT(NSAccessibilityContentsAttribute, accessibilityContents) \
    OBJECT(NSAccessibilityTabsAttribute, accessibilityTabs) \
    OBJECT(NSAccessibilityRowsAttribute, accessibilityRows) \
    OBJECT(NSAccessibilityColumnsAttribute, accessibilityColumns) \
    OBJECT(NSAccessibilitySelectedTextAttribute, accessibilitySelectedText) \
    OBJECT(NSAccessibilitySelectedTextRangesAttribute, accessibilitySelectedTextRanges) \
    FLAG(NSAccessibilityEnabledAttribute, isAccessibilityEnabled) \
    FLAG(NSAccessibilityFocusedAttribute, isAccessibilityFocused) \
    FLAG(NSAccessibilitySelectedAttribute, isAccessibilitySelected) \
    FLAG(NSAccessibilityExpandedAttribute, isAccessibilityExpanded) \
    FLAG(NSAccessibilityEditedAttribute, isAccessibilityEdited) \
    INTEGER(NSAccessibilityIndexAttribute, accessibilityIndex) \
    INTEGER(NSAccessibilityNumberOfCharactersAttribute, accessibilityNumberOfCharacters) \
    INTEGER(NSAccessibilityInsertionPointLineNumberAttribute, accessibilityInsertionPointLineNumber) \
    RANGE(NSAccessibilitySelectedTextRangeAttribute, accessibilitySelectedTextRange) \
    RANGE(NSAccessibilityVisibleCharacterRangeAttribute, accessibilityVisibleCharacterRange)

/* The 10.10 getter's answer to a 10.9 attribute, boxed as 10.9 boxes it; nil where self has no getter for it or the
   getter answers nil (or NSNotFound for a range). */
static inline __attribute__((always_inline)) id answer(NSObject *self, NSString *a) {
#define OBJECT(constant, getter) \
    if ([a isEqualToString:constant]) return [self respondsToSelector:@selector(getter)] ? [self getter] : nil;
#define FLAG(constant, getter) \
    if ([a isEqualToString:constant]) \
        return [self respondsToSelector:@selector(getter)] ? [NSNumber numberWithBool:[self getter]] : nil;
#define INTEGER(constant, getter) \
    if ([a isEqualToString:constant]) \
        return [self respondsToSelector:@selector(getter)] ? [NSNumber numberWithInteger:[self getter]] : nil;
#define RANGE(constant, getter) \
    if ([a isEqualToString:constant]) { \
        if (![self respondsToSelector:@selector(getter)]) return nil; \
        NSRange r = [self getter]; \
        return r.location == NSNotFound ? nil : [NSValue valueWithRange:r]; \
    }
    MAPPED(OBJECT, FLAG, INTEGER, RANGE)
#undef OBJECT
#undef FLAG
#undef INTEGER
#undef RANGE
    /* platform: 10.9's AXPosition is the element's lower-left corner in screen coordinates, as 10.10's frame origin is */
    if ([a isEqualToString:NSAccessibilityPositionAttribute] || [a isEqualToString:NSAccessibilitySizeAttribute]) {
        if (![self respondsToSelector:@selector(accessibilityFrame)]) return nil;
        NSRect frame = [self accessibilityFrame];
        if ([a isEqualToString:NSAccessibilityPositionAttribute]) return [NSValue valueWithPoint:frame.origin];
        return [NSValue valueWithSize:frame.size];
    }
    return nil;
}

/* Every 10.9 attribute answer() maps, in the order 10.9 lists its own. */
static __attribute__((unused)) NSArray *mappedAttributes(void) {
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

/* Settable through a 10.10 setter the class implements. Not the label, role, children or selected-text-range setters:
   Recaulk's setter groups give every view and cell those, so responding to them says nothing about this class. */
static inline __attribute__((always_inline)) BOOL settable(NSObject *self, NSString *a) {
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

/* The 10.10 parameterized getters, each by its 10.9 parameterized attribute: an index or line parameter is an
   NSNumber, a range an NSValue of a range, a position an NSValue of a point. */
static inline __attribute__((always_inline)) id parameterized(NSObject *self, NSString *a, id p) {
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

/* Each 10.9 action with the 10.10 perform method that does it: the action is offered where self implements the
   method. *known says whether self implements it, and the method is called only when call is YES. */
static inline __attribute__((always_inline)) BOOL action(NSObject *self, NSString *a, BOOL call, BOOL *known) {
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

#endif
