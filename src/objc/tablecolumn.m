/* -[NSTableColumn title] and -setTitle: (10.10): the header cell's string, which 10.9 has. self is typed
   NSTableColumn * and the cell NSCell *, so a consumer's strict guard can close each send. 10.10 declares title
   non-null and copies it: a nil title is stored as the empty string, and the cell copies a mutable one. */
#import "workspace-private.h"
NSString *__recaulk_objc_tablecolumn_title(NSTableColumn *self, SEL _cmd) {
    (void)_cmd;
    NSCell *cell = [self headerCell];
    return [cell stringValue];
}
void __recaulk_objc_tablecolumn_set_title(NSTableColumn *self, SEL _cmd, NSString *title) {
    (void)_cmd;
    NSCell *cell = [self headerCell];
    [cell setStringValue:title ? title : @""];
}
