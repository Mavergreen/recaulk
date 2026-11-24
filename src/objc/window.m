/* -[NSWindow titlebarAppearsTransparent] and -setTitlebarAppearsTransparent: (10.10). 10.9 draws no transparent
   titlebar, so the window reads NO, as it looks, and the setter accepts YES and changes nothing. self is typed
   NSWindow *, and neither sends a message, so a consumer's strict guard has nothing to close. */
#import "workspace-private.h"
BOOL __recaulk_objc_window_titlebar_appears_transparent(NSWindow *self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return NO;
}
void __recaulk_objc_window_set_titlebar_appears_transparent(NSWindow *self, SEL _cmd, BOOL flag) {
    (void)self;
    (void)_cmd;
    (void)flag;
}
