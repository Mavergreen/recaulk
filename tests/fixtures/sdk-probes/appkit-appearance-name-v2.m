#import <Cocoa/Cocoa.h>
BOOL probe(NSAppearance *a) { return [a.name isEqualToString:NSAppearanceNameAqua]; }
NSString *probeBest(NSAppearance *a) {
    if (@available(macOS 10.14, *))
        return [a bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua]];
    return a.name;
}
