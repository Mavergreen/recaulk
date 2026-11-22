#import <Cocoa/Cocoa.h>
@interface ProbeTab : NSObject <NSAccessibilityRadioButton>
@end
@implementation ProbeTab
- (NSRect)accessibilityFrame { return NSZeroRect; }
- (id)accessibilityParent { return nil; }
- (NSString *)accessibilityLabel { return @"tab"; }
- (BOOL)accessibilityPerformPress { return YES; }
- (NSNumber *)accessibilityValue { return @YES; }
@end
@interface ProbeBar : NSView <NSAccessibilityGroup>
@end
@implementation ProbeBar
- (NSRect)accessibilityFrame { return [self frame]; }
- (id)accessibilityParent { return [self superview]; }
@end
@interface ProbeText : NSObject <NSAccessibilityNavigableStaticText, NSAccessibilityCheckBox>
@end
id<NSAccessibilityElement> probeElement(ProbeBar *b) { return b; }
id<NSAccessibilitySwitch> probeSwitch(id<NSAccessibilitySwitch> s) { return s; }
