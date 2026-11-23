#import <Cocoa/Cocoa.h>
void probe(NSTextAttachment *t, NSImage *i) { if (@available(macOS 10.11, *)) t.image = i; }
