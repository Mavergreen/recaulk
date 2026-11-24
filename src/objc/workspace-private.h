#ifndef RECAULK_WORKSPACE_PRIVATE_H
#define RECAULK_WORKSPACE_PRIVATE_H
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
typedef struct {
    NSRunningApplication *(*launch)(NSWorkspace *, NSURL *, NSWorkspaceLaunchOptions, NSDictionary *, NSError **);
    NSRunningApplication *(*lookup)(pid_t);
    OSStatus (*send)(NSAppleEventDescriptor *);
    BOOL (*note_recents)(NSArray *, NSWorkspaceLaunchOptions, NSError **);
    /* One Launch Services request carrying app, every URL, flags, environment,
     * arguments and initial event; LS delivers the URLs. NULL: legacy path. */
    OSStatus (*ls_open)(NSArray *urls, NSURL *app, LSLaunchFlags, NSDictionary *environment, NSArray *arguments, NSAppleEventDescriptor *initial, pid_t *pid);
} RecaulkWorkspaceOps;
/* ls_open's own status when the application URL can't be resolved; outside
 * the OSStatus ranges Launch Services and the File Manager return. */
#define RECAULK_LS_NO_APPLICATION ((OSStatus)-1974001)
NSArray *__recaulk_workspace_url_events(NSArray *, NSWorkspaceLaunchOptions, NSError **);
BOOL __recaulk_workspace_note_recent_files(NSArray *, NSWorkspaceLaunchOptions, NSError **);
NSRunningApplication *__recaulk_workspace_open_urls_with_ops(NSWorkspace *, NSArray *, NSURL *, NSWorkspaceLaunchOptions, NSDictionary *, NSError **, const RecaulkWorkspaceOps *);
NSRunningApplication *__recaulk_objc_workspace_open_urls(id, SEL, NSArray *, NSURL *, NSWorkspaceLaunchOptions, NSDictionary *, NSError **);
BOOL __recaulk_objc_voiceover_enabled_in(CFStringRef);
BOOL __recaulk_objc_workspace_is_voiceover_enabled(id, SEL);
BOOL __recaulk_objc_workspace_should_reduce_motion(id, SEL);
NSString *__recaulk_objc_tablecolumn_title(NSTableColumn *, SEL);
void __recaulk_objc_tablecolumn_set_title(NSTableColumn *, SEL, NSString *);
void __recaulk_objc_register_tablecolumn_class(Class);
BOOL __recaulk_objc_control_uses_single_line_mode(NSControl *, SEL);
void __recaulk_objc_control_set_uses_single_line_mode(NSControl *, SEL, BOOL);
void __recaulk_objc_register_control_class(Class);
BOOL __recaulk_objc_window_titlebar_appears_transparent(NSWindow *, SEL);
void __recaulk_objc_window_set_titlebar_appears_transparent(NSWindow *, SEL, BOOL);
void __recaulk_objc_register_window_class(Class);
void __recaulk_objc_activate(void);
NSColor *__recaulk_objc_color_label(Class, SEL);
NSColor *__recaulk_objc_color_link(Class, SEL);
void __recaulk_objc_activate_color(void);
NSGraphicsContext *__recaulk_objc_graphics_context_with_cgcontext(Class, SEL, CGContextRef, BOOL);
void __recaulk_objc_activate_graphics_context(void);
void __recaulk_objc_ax_view_set(NSView *, id, NSString *);
void __recaulk_objc_ax_cell_set(NSCell *, id, NSString *);
id __recaulk_objc_ax_view_value(NSView *, NSString *);
id __recaulk_objc_ax_cell_value(NSCell *, NSString *);
NSRange __recaulk_objc_ax_range(id);
NSRect __recaulk_objc_ax_frame(id, id);
void __recaulk_objc_view_set_accessibility_label(NSView *, SEL, NSString *);
NSString *__recaulk_objc_view_accessibility_label(NSView *, SEL);
void __recaulk_objc_view_set_accessibility_role(NSView *, SEL, NSString *);
NSString *__recaulk_objc_view_accessibility_role(NSView *, SEL);
void __recaulk_objc_view_set_accessibility_children(NSView *, SEL, NSArray *);
NSArray *__recaulk_objc_view_accessibility_children(NSView *, SEL);
void __recaulk_objc_view_set_accessibility_selected_text_range(NSView *, SEL, NSRange);
NSRange __recaulk_objc_view_accessibility_selected_text_range(NSView *, SEL);
NSRect __recaulk_objc_view_accessibility_frame(NSView *, SEL);
void __recaulk_objc_activate_view_accessibility(void);
void __recaulk_objc_cell_set_accessibility_label(NSCell *, SEL, NSString *);
NSString *__recaulk_objc_cell_accessibility_label(NSCell *, SEL);
void __recaulk_objc_cell_set_accessibility_role(NSCell *, SEL, NSString *);
NSString *__recaulk_objc_cell_accessibility_role(NSCell *, SEL);
void __recaulk_objc_cell_set_accessibility_children(NSCell *, SEL, NSArray *);
NSArray *__recaulk_objc_cell_accessibility_children(NSCell *, SEL);
void __recaulk_objc_cell_set_accessibility_selected_text_range(NSCell *, SEL, NSRange);
NSRange __recaulk_objc_cell_accessibility_selected_text_range(NSCell *, SEL);
NSRect __recaulk_objc_cell_accessibility_frame(NSCell *, SEL);
void __recaulk_objc_activate_cell_accessibility(void);
void __recaulk_objc_register_workspace_class(Class);
#endif
