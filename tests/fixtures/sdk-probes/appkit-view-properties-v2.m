#import <Cocoa/Cocoa.h>
void probe(NSView *v) { v.hidden = !v.hidden; }
@interface ProbeView : NSView
@end
@implementation ProbeView
- (NSString *)accessibilityLabel { return @"tabs"; }
- (NSString *)accessibilityRole { return NSAccessibilityTabGroupRole; }
- (NSArray *)accessibilityChildren { return @[]; }
@end
void probeAX(NSView *v) {
    if ([v respondsToSelector:@selector(setAccessibilityLabel:)]) v.accessibilityLabel = v.accessibilityRole;
    (void)v.accessibilityChildren;
}
