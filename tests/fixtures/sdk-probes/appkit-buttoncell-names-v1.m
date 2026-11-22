#import <Cocoa/Cocoa.h>
void probe(NSButton *b) {
    NSButtonType t = NSButtonTypeSwitch;
    switch (t) {
    case NSButtonTypeMomentaryLight: case NSButtonTypePushOnPushOff: case NSButtonTypeToggle:
    case NSButtonTypeSwitch: case NSButtonTypeRadio: case NSButtonTypeMomentaryChange:
    case NSButtonTypeOnOff: case NSButtonTypeMomentaryPushIn: break;
    }
    [b setButtonType:t];
    NSBezelStyle s = NSBezelStyleRounded;
    switch (s) {
    case NSBezelStyleRounded: case NSBezelStyleRegularSquare: case NSBezelStyleThickSquare:
    case NSBezelStyleThickerSquare: case NSBezelStyleDisclosure: case NSBezelStyleShadowlessSquare:
    case NSBezelStyleCircular: case NSBezelStyleTexturedSquare: case NSBezelStyleHelpButton:
    case NSBezelStyleSmallSquare: case NSBezelStyleTexturedRounded: case NSBezelStyleRoundRect:
    case NSBezelStyleRecessed: case NSBezelStyleRoundedDisclosure: case NSBezelStyleInline: break;
    default: break;
    }
    [b setBezelStyle:s];
}
