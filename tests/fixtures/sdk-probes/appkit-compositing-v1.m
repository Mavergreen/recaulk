#import <Cocoa/Cocoa.h>
void probe(NSImage *i) {
    NSCompositingOperation ops[] = { NSCompositingOperationClear, NSCompositingOperationCopy,
        NSCompositingOperationSourceOver, NSCompositingOperationSourceIn, NSCompositingOperationSourceOut,
        NSCompositingOperationSourceAtop, NSCompositingOperationDestinationOver, NSCompositingOperationDestinationIn,
        NSCompositingOperationDestinationOut, NSCompositingOperationDestinationAtop, NSCompositingOperationXOR,
        NSCompositingOperationPlusDarker, NSCompositingOperationPlusLighter };
    [i drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:ops[2] fraction:1];
}
