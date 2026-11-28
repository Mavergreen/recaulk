#ifndef RECAULK_ACCESSIBILITY_ELEMENT_H
#define RECAULK_ACCESSIBILITY_ELEMENT_H
/* RecaulkAccessibilityElement, lib/stand-in/libRecaulkAppKit.dylib's shim for 10.10's NSAccessibilityElement:
 * subclass it in place of NSAccessibilityElement and link the dylib (README.md "Stand-in classes"). Where AppKit has
 * NSAccessibilityElement (10.10 and later) the shim inherits from it; on 10.9 the dylib adds these methods itself.
 * 10.9's attribute API (accessibilityAttributeNames and its kin) answers from them; AppKit declares that API on NSObject.
 * spec: MacOSX10.10.sdk NSAccessibilityElement.h and NSAccessibilityProtocols.h -- the names and types, as the
 * stand-in adds them in src/standins/RecaulkAccessibilityElement.m. The parent is not retained there either. */
#import <AppKit/AppKit.h>

@interface RecaulkAccessibilityElement : NSObject
/* frame is in screen coordinates; parent is not retained */
+ (id)accessibilityElementWithRole:(NSString *)role frame:(NSRect)frame label:(NSString *)label parent:(id)parent;
/* appends to accessibilityChildren and makes self the child's parent */
- (void)accessibilityAddChildElement:(RecaulkAccessibilityElement *)childElement;
/* relative to the parent's frame; where set, accessibilityFrame follows the parent */
@property NSRect accessibilityFrameInParentSpace;
@property NSRect accessibilityFrame;
@property (copy) NSString *accessibilityRole;
@property (copy) NSString *accessibilitySubrole;
@property (copy) NSString *accessibilityRoleDescription;
@property (copy) NSString *accessibilityLabel;
@property (copy) NSString *accessibilityTitle;
@property (copy) NSString *accessibilityHelp;
@property (copy) NSString *accessibilityIdentifier;
@property (retain) id accessibilityValue;
@property (assign) id accessibilityParent;
@property (copy) NSArray *accessibilityChildren;
@property (getter=isAccessibilityEnabled) BOOL accessibilityEnabled;
@property (getter=isAccessibilityFocused) BOOL accessibilityFocused;
@property (getter=isAccessibilitySelected) BOOL accessibilitySelected;
@property (getter=isAccessibilityElement) BOOL accessibilityElement;
@property (readonly) id accessibilityWindow;
@property (readonly) id accessibilityTopLevelUIElement;
@end

#endif
