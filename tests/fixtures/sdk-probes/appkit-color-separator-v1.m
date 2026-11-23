#import <Cocoa/Cocoa.h>
NSColor *probe(void) {
    if (@available(macOS 10.14, *)) return [NSColor separatorColor];
    return [NSColor gridColor];
}
