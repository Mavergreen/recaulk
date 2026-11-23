#import <Cocoa/Cocoa.h>
void probe(NSAlert *a) {
    [a setAlertStyle:[a alertStyle] == NSAlertStyleWarning ? NSAlertStyleCritical : NSAlertStyleInformational];
}
NSWindow *probeSheet(id sender) { return [sender window].sheetParent; }
// needs: appkit-window-v4
