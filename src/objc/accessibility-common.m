/* What the NSView and NSCell accessibility groups (accessibility-view.m, accessibility-cell.m) share. 10.9 answers
 * VoiceOver from its attribute API, so a 10.10 setter writes the 10.9 attribute's override
 * (-accessibilitySetOverrideValue:forAttribute:) and a getter reads that override, or else the attribute's 10.9 value.
 * Nothing here registers anything, so linking it activates no group. */
#import "workspace-private.h"

/* platform: 10.9 AppKit, NSObject(NSAccessibilityOverriddenAttributes) -- the overrides set so far. 10.9's
   -accessibilityAttributeValue: never consults them (only the accessibility server does), so a getter reads them
   here to return what its setter set. */
@interface NSObject (RecaulkAccessibilityOverrides)
- (NSDictionary *)accessibilityOverriddenAttributes;
@end

/* spec: tests/objc-source-receipt.sh -- every send below has a receiver of a concrete class, never id, so a consumer's
   strict analysis closes it from the source receipt */

/* platform: 10.9 AppKit -- a control is ignored and its cell is the element VoiceOver sees, and the server drops an
   ignored element's overrides (-accessibilityAllowsOverriddenAttributesWhenIgnored is NO), so a control's properties
   live on its cell, as 10.10's NSControl forwards them to its cell */
static NSCell *controlCell(NSView *view) {
    if (![view isKindOfClass:[NSControl class]]) return nil;
    NSControl *control = (NSControl *)view;
    if (![control accessibilityIsIgnored]) return nil;
    NSCell *cell = [control cell];
    return cell && ![cell accessibilityIsIgnored] ? cell : nil;
}

static void setOverride(NSObject *element, id value, NSString *attribute) {
    [element accessibilitySetOverrideValue:value forAttribute:attribute];
}
static id override(NSObject *element, NSString *attribute) {
    if (![element respondsToSelector:@selector(accessibilityOverriddenAttributes)]) return nil;
    NSDictionary *overrides = [element accessibilityOverriddenAttributes];
    return [overrides objectForKey:attribute];
}

void __recaulk_objc_ax_cell_set(NSCell *cell, id value, NSString *attribute) { setOverride(cell, value, attribute); }
void __recaulk_objc_ax_view_set(NSView *view, id value, NSString *attribute) {
    NSCell *cell = controlCell(view);
    if (cell) setOverride(cell, value, attribute);
    else setOverride(view, value, attribute);
}

/* The override, else 10.9's value; nil where the element has neither, instead of 10.9's unsupported-attribute throw. */
id __recaulk_objc_ax_cell_value(NSCell *cell, NSString *attribute) {
    id overridden = override(cell, attribute);
    if (overridden) return overridden;
    NSArray *names = [cell accessibilityAttributeNames];
    if (![names containsObject:attribute]) return nil;
    @try {
        return [cell accessibilityAttributeValue:attribute];
    } @catch (NSException *e) {
        (void)e;
        return nil;
    }
}
id __recaulk_objc_ax_view_value(NSView *view, NSString *attribute) {
    NSCell *cell = controlCell(view);
    if (cell) return __recaulk_objc_ax_cell_value(cell, attribute);
    id overridden = override(view, attribute);
    if (overridden) return overridden;
    NSArray *names = [view accessibilityAttributeNames];
    if (![names containsObject:attribute]) return nil;
    @try {
        return [view accessibilityAttributeValue:attribute];
    } @catch (NSException *e) {
        (void)e;
        return nil;
    }
}

/* An absent or non-range value reads {NSNotFound, 0}, as 10.10's default does. */
NSRange __recaulk_objc_ax_range(id value) {
    if (![value isKindOfClass:[NSValue class]]) return NSMakeRange(NSNotFound, 0);
    NSValue *range = value;
    return [range rangeValue];
}
/* 10.9's position is the element's lower-left corner in screen coordinates, so it and the size are the 10.10 frame;
   NSZeroRect where either is absent. */
NSRect __recaulk_objc_ax_frame(id position, id size) {
    if (![position isKindOfClass:[NSValue class]] || ![size isKindOfClass:[NSValue class]]) return NSZeroRect;
    NSValue *origin = position, *extent = size;
    NSRect frame = {[origin pointValue], [extent sizeValue]};
    return frame;
}
