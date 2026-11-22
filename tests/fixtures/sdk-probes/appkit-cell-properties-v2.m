#import <Cocoa/Cocoa.h>
void probe(NSCell *c) { c.highlighted = !c.highlighted; }
void probeSize(NSCell *c) {
    NSControlSize s = [c controlSize];
    [c setControlSize:s == NSControlSizeRegular ? NSControlSizeSmall : NSControlSizeMini];
}
