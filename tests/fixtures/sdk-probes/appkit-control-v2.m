#import <Cocoa/Cocoa.h>
void probe(NSControl *c) { c.enabled = c.continuous; c.continuous = c.enabled; }
void probeSingle(NSTextField *f) { f.usesSingleLineMode = !f.usesSingleLineMode; }
