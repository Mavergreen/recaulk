// needs: appkit-window-v1
// weak: _OBJC_CLASS_$_NSTitlebarAccessoryViewController
#import <Cocoa/Cocoa.h>
@interface Probe : NSTitlebarAccessoryViewController
@end
@implementation Probe
- (void)awakeFromNib { self.layoutAttribute = NSLayoutAttributeRight; }
- (void)viewDidLoad { [super viewDidLoad]; }
- (void)viewWillAppear { [super viewWillAppear]; }
- (void)viewDidAppear { [super viewDidAppear]; }
- (void)viewWillDisappear { [super viewWillDisappear]; }
- (void)viewDidDisappear { [super viewDidDisappear]; }
- (void)viewWillLayout { [super viewWillLayout]; }
- (void)viewDidLayout { [super viewDidLayout]; }
@end
void probe(NSWindow *w, Probe *p) {
    if ([w respondsToSelector:@selector(addTitlebarAccessoryViewController:)]) { [w addTitlebarAccessoryViewController:p]; }
}
