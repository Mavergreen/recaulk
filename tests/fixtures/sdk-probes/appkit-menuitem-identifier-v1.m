#import <Cocoa/Cocoa.h>
void probe(NSMenuItem *i) { i.identifier = [i.identifier stringByAppendingString:@"."]; }
