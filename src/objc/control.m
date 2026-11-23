/* -[NSControl usesSingleLineMode] and -setUsesSingleLineMode: (10.10): the control's cell's, which 10.9's NSCell has
   (10.6). self is typed NSControl * and the cell NSCell *, so a consumer's strict guard can close each send. A control
   with no cell reads NO and ignores the setter, as a message to nil would. */
#import "workspace-private.h"
BOOL __recaulk_objc_control_uses_single_line_mode(NSControl *self, SEL _cmd) {
    (void)_cmd;
    NSCell *cell = [self cell];
    return [cell usesSingleLineMode];
}
void __recaulk_objc_control_set_uses_single_line_mode(NSControl *self, SEL _cmd, BOOL flag) {
    (void)_cmd;
    NSCell *cell = [self cell];
    [cell setUsesSingleLineMode:flag];
}
