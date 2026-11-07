// needs: appkit-window-v1
// weak: _OBJC_CLASS_$_NSTitlebarAccessoryViewController
#import <Cocoa/Cocoa.h>
@interface Probe : NSTitlebarAccessoryViewController
@end
@implementation Probe
- (void)awakeFromNib { self.layoutAttribute = NSLayoutAttributeRight; }
@end
void probe(NSWindow *w, Probe *p) {
    if ([w respondsToSelector:@selector(addTitlebarAccessoryViewController:)]) { [w addTitlebarAccessoryViewController:p]; }
}
