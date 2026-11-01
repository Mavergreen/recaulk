#ifndef RECAULK_WORKSPACE_PRIVATE_H
#define RECAULK_WORKSPACE_PRIVATE_H
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
typedef struct {
    NSRunningApplication *(*launch)(NSWorkspace *, NSURL *, NSWorkspaceLaunchOptions, NSDictionary *, NSError **);
    NSRunningApplication *(*lookup)(pid_t);
    OSStatus (*send)(NSAppleEventDescriptor *);
    BOOL (*note_recents)(NSArray *, NSWorkspaceLaunchOptions, NSError **);
} RecaulkWorkspaceOps;
NSArray *recaulk_workspace_url_events(NSArray *, NSWorkspaceLaunchOptions, NSError **);
BOOL recaulk_workspace_note_recent_files(NSArray *, NSWorkspaceLaunchOptions, NSError **);
NSRunningApplication *recaulk_workspace_open_urls_with_ops(NSWorkspace *, NSArray *, NSURL *, NSWorkspaceLaunchOptions, NSDictionary *, NSError **, const RecaulkWorkspaceOps *);
NSRunningApplication *__recaulk_objc_workspace_open_urls(id, SEL, NSArray *, NSURL *, NSWorkspaceLaunchOptions, NSDictionary *, NSError **);
#endif
