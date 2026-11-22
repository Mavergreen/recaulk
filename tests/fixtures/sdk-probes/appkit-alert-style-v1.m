#import <Cocoa/Cocoa.h>
void probe(NSAlert *a) {
    [a setAlertStyle:[a alertStyle] == NSAlertStyleWarning ? NSAlertStyleCritical : NSAlertStyleInformational];
}
