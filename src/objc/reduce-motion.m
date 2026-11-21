/* -[NSWorkspace accessibilityDisplayShouldReduceMotion] (10.12). No messages and no frameworks. */
#import "workspace-private.h"

/* platform: 10.9 has no reduce-motion setting (Accessibility's Display pane gained it in 10.12), so motion is never
   reduced; with no setting to change, there is no key-value observing change to post either. */
BOOL __recaulk_objc_workspace_should_reduce_motion(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return NO;
}
