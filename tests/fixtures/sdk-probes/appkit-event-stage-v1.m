#import <Cocoa/Cocoa.h>
NSInteger probe(NSEvent *e) { return [e respondsToSelector:@selector(stage)] ? e.stage : 0; }
