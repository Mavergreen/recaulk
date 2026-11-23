#import <Cocoa/Cocoa.h>
@interface ProbeWindow : NSWindow
@end
@implementation ProbeWindow
- (instancetype)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d {
    return [super initWithContentRect:r styleMask:s backing:b defer:d];
}
@end
NSWindowStyleMask probeMask(NSWindow *w) {
    NSWindowStyleMask all = NSWindowStyleMaskBorderless | NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskTexturedBackground |
        NSWindowStyleMaskUnifiedTitleAndToolbar | NSWindowStyleMaskFullScreen | NSWindowStyleMaskUtilityWindow |
        NSWindowStyleMaskDocModalWindow | NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskHUDWindow;
    return [w styleMask] & all;
}
void probeTabbing(NSWindow *w) {
    if ([w respondsToSelector:@selector(setTabbingMode:)]) w.tabbingMode = NSWindowTabbingModeDisallowed;
    NSWindowTabbingMode m = NSWindowTabbingModeAutomatic;
    (void)m; (void)NSWindowTabbingModePreferred;
}
void probeFullScreen(NSWindow *w) { w.collectionBehavior |= NSWindowCollectionBehaviorFullScreenNone; }
BOOL probeLevel(NSWindow *w) { NSWindowLevel l = [w level]; return w.visible && l > NSNormalWindowLevel; }
NSWindow *probeSheet(NSWindow *w) { return w.sheetParent; }
