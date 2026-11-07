#import <Cocoa/Cocoa.h>
void probe(NSControl *c) { c.enabled = c.continuous; c.continuous = c.enabled; }
