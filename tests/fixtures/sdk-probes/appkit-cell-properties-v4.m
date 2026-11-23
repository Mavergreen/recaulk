#import <Cocoa/Cocoa.h>
void probe(NSCell *c) { c.highlighted = !c.highlighted; }
void probeSize(NSCell *c) {
    NSControlSize s = [c controlSize];
    [c setControlSize:s == NSControlSizeRegular ? NSControlSizeSmall : NSControlSizeMini];
}
NSBackgroundStyle probeStyle(NSCell *c) { return [c backgroundStyle] == NSBackgroundStyleEmphasized ? NSBackgroundStyleNormal : NSBackgroundStyleEmphasized; }
@interface ProbeCell : NSCell
@end
@implementation ProbeCell
- (NSString *)accessibilityLabel { return self.title; }
- (NSString *)accessibilityRole { return NSAccessibilityRadioButtonRole; }
- (NSArray *)accessibilityChildren { return nil; }
@end
NSString *probeAX(NSCell *c) { return c.accessibilityLabel ?: c.accessibilityRole; }
