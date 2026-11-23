// weak: _OBJC_CLASS_$_NSVisualEffectView
#import <Cocoa/Cocoa.h>
@interface ProbeVibrant : NSVisualEffectView
@end
@implementation ProbeVibrant
- (BOOL)allowsVibrancy { return NO; }
@end
NSView *probe(NSRect r) {
    NSView *v = [[NSView alloc] initWithFrame:r];
    [v setHidden:YES];
    if (![NSVisualEffectView class]) return v;
    NSVisualEffectView *e = [[ProbeVibrant alloc] initWithFrame:r];
    e.material = NSVisualEffectMaterialTitlebar;
    e.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    e.state = NSVisualEffectStateActive;
    if (e.allowsVibrancy || e.material == NSVisualEffectMaterialMenu || e.blendingMode == NSVisualEffectBlendingModeBehindWindow)
        return v;
    return e;
}
NSAutoresizingMaskOptions probeMaskOptions(NSView *v) { return [v autoresizingMask] | NSViewWidthSizable; }
