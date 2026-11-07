#import <Cocoa/Cocoa.h>
@interface ProbeWindow : NSWindow
@end
@implementation ProbeWindow
- (instancetype)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d {
    return [super initWithContentRect:r styleMask:s backing:b defer:d];
}
@end
