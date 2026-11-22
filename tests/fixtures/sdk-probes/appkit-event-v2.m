#import <Cocoa/Cocoa.h>
NSInteger probe(NSEvent *e) { return [e respondsToSelector:@selector(stage)] ? e.stage : 0; }
BOOL probeNames(NSEvent *e) {
    NSEventModifierFlags f = [e modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    NSEventMask m = NSEventMaskKeyDown | NSEventMaskFlagsChanged | NSEventMaskLeftMouseDown | NSEventMaskScrollWheel;
    (void)m;
    switch ([e type]) {
    case NSEventTypeKeyDown: case NSEventTypeKeyUp: case NSEventTypeFlagsChanged:
    case NSEventTypeLeftMouseDown: case NSEventTypeOtherMouseDragged: case NSEventTypeScrollWheel:
        break;
    default:
        return (f & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift |
                     NSEventModifierFlagControl | NSEventModifierFlagCapsLock | NSEventModifierFlagFunction |
                     NSEventModifierFlagNumericPad | NSEventModifierFlagHelp)) != 0;
    }
    return NSEventMaskAny != 0;
}
