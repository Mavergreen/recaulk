#import <Cocoa/Cocoa.h>
void probe(NSTableColumn *c) { c.title = [c.title stringByAppendingString:@"!"]; }
