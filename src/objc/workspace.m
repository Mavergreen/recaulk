/* Missing-method body, MRC/+0. Registration/link-root live separately. */
#import "workspace-private.h"
#include <errno.h>
static NSRunningApplication *failure(NSError **out, NSString *domain, NSInteger code, NSString *reason) {
    if (out) *out=[NSError errorWithDomain:domain code:code userInfo:@{NSLocalizedDescriptionKey:reason}];
    return nil;
}
static NSRunningApplication *launch(NSWorkspace *workspace, NSURL *url, NSWorkspaceLaunchOptions options, NSDictionary *configuration, NSError **error) {
    return [workspace launchApplicationAtURL:url options:options configuration:configuration error:error];
}
static NSRunningApplication *lookup(pid_t pid) {
    /* Mavericks can publish the bundle URL before the executable architecture.
     * Measured populated identity at ~84ms while finishedLaunching was FALSE.
     * Allow a bounded registration grace, not an application-finish wait. No
     * caller run loop, worker surviving return, flag changes or provisional +0
     * success. After the polling budget the core still validates/fails usefully.
     * Budget excludes time spent inside an individual public lookup call. */
    NSTimeInterval deadline=[[NSProcessInfo processInfo] systemUptime]+0.25;
    for (;;) {
        NSRunningApplication *application=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if ((application && application.processIdentifier!=pid) ||
            (application.bundleURL && application.executableArchitecture>0) ||
            [[NSProcessInfo processInfo] systemUptime]>=deadline) return application;
        [NSThread sleepForTimeInterval:0.002];
    }
}
static OSStatus sendEvent(NSAppleEventDescriptor *event) {
    return AESendMessage(event.aeDesc,NULL,kAENoReply|kAENeverInteract,kAEDefaultTimeout);
}
static OSStatus lsOpen(NSArray *urls, NSURL *app, LSLaunchFlags flags, NSDictionary *environment, NSArray *arguments,
    NSAppleEventDescriptor *initial, pid_t *pid) {
    FSRef ref;
    if (![app isFileURL] || !CFURLGetFSRef((CFURLRef)app,&ref)) return fnfErr;
    LSApplicationParameters params={0,flags,&ref,NULL,(CFDictionaryRef)environment,(CFArrayRef)arguments,
        initial ? (AppleEvent *)initial.aeDesc : NULL};
    ProcessSerialNumber psn={0,kNoProcess};
    /* With an explicit application LS ignores the role, launches if needed and
     * delivers every URL itself (GURL; file URLs as documents). */
    OSStatus status=urls.count ? LSOpenURLsWithRole((CFArrayRef)urls,kLSRolesAll,NULL,&params,&psn,1)
                               : LSOpenApplication(&params,&psn);
    if (status!=noErr) return status;
    return GetProcessPID(&psn,pid);
}
static const RecaulkWorkspaceOps publicOps={launch,lookup,sendEvent,__recaulk_workspace_note_recent_files,lsOpen};
/* NSWorkspaceLaunchOptions bits whose LSLaunchFlags values are identical. */
static const NSWorkspaceLaunchOptions lsShared=NSWorkspaceLaunchAndPrint|NSWorkspaceLaunchWithErrorPresentation|
    NSWorkspaceLaunchInhibitingBackgroundOnly|NSWorkspaceLaunchWithoutAddingToRecents|NSWorkspaceLaunchWithoutActivation|
    NSWorkspaceLaunchAsync|NSWorkspaceLaunchNewInstance|NSWorkspaceLaunchAndHide|NSWorkspaceLaunchAndHideOthers;
static NSRunningApplication *openWithLaunchServices(NSArray *urls, NSArray *valid, NSURL *app, NSWorkspaceLaunchOptions options,
    NSDictionary *configuration, NSError **error, const RecaulkWorkspaceOps *ops) {
    id environment=[configuration objectForKey:NSWorkspaceLaunchConfigurationEnvironment];
    id arguments=[configuration objectForKey:NSWorkspaceLaunchConfigurationArguments];
    id custom=[configuration objectForKey:NSWorkspaceLaunchConfigurationAppleEvent];
    if (custom && ![custom isKindOfClass:[NSAppleEventDescriptor class]])
        [NSException raise:NSInvalidArgumentException format:@"Initial Apple event must be an NSAppleEventDescriptor"];
    if ((environment && ![environment isKindOfClass:[NSDictionary class]]) || (arguments && ![arguments isKindOfClass:[NSArray class]]))
        [NSException raise:NSInvalidArgumentException format:@"Launch environment must be a dictionary and arguments an array"];
    pid_t pid=0;
    OSStatus status=ops->ls_open(valid,app,(LSLaunchFlags)(options&lsShared),environment,arguments,
        custom ? [[custom copy] autorelease] : nil,&pid);
    /* A missing application is Cocoa 260, as the native method reports it. */
    if (status==fnfErr) return failure(error,NSCocoaErrorDomain,NSFileReadNoSuchFileError,@"The application could not be found.");
    if (status!=noErr) return failure(error,NSOSStatusErrorDomain,status,@"Launch Services could not open the URLs with the application.");
    NSRunningApplication *selected=pid>0 ? ops->lookup(pid) : nil;
    if (!selected || selected.processIdentifier!=pid || !selected.bundleURL || selected.executableArchitecture<=0)
        return failure(error,NSPOSIXErrorDomain,ESRCH,@"Launch Services opened every URL, but the application's populated process identity could not be reacquired.");
    if (!urls.count) return failure(error,NSCocoaErrorDomain,NSFileReadUnknownError,@"The URL array is empty; application launch or initial-event delivery may have occurred.");
    return selected;
}
NSRunningApplication *__recaulk_workspace_open_urls_with_ops(NSWorkspace *workspace, NSArray *urls, NSURL *app,
    NSWorkspaceLaunchOptions options, NSDictionary *configuration, NSError **error, const RecaulkWorkspaceOps *provided) {
    if (!urls || !app) [NSException raise:NSInternalInconsistencyException format:@"Invalid parameter: urls and applicationURL must not be nil"];
    if (![urls isKindOfClass:[NSArray class]] || ![app isKindOfClass:[NSURL class]] ||
        (configuration && ![configuration isKindOfClass:[NSDictionary class]]))
        [NSException raise:NSInvalidArgumentException format:@"Invalid workspace URL array, application URL or configuration type"];
    const RecaulkWorkspaceOps *ops=provided ?: &publicOps;
    NSMutableArray *valid=[NSMutableArray array], *files=[NSMutableArray array];
    for (id value in urls) if ([value isKindOfClass:[NSURL class]]) {
        [valid addObject:value]; if ([value isFileURL]) [files addObject:value];
    }
    /* Launch Services has no architecture parameter: only that request keeps the
     * launch-then-send path, whose later URLs wait on the identity lookup. */
    if (ops->ls_open && ![configuration objectForKey:NSWorkspaceLaunchConfigurationArchitecture])
        return openWithLaunchServices(urls,valid,app,options,configuration,error,ops);
    NSError *local=nil;
    NSArray *events=__recaulk_workspace_url_events(valid,options,&local);
    if (!events) { if (error) *error=local; return nil; }
    NSMutableDictionary *copy=configuration ? [[configuration mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    NSAppleEventDescriptor *custom=[copy objectForKey:NSWorkspaceLaunchConfigurationAppleEvent];
    NSUInteger next=0;
    if (custom) {
        if (![custom isKindOfClass:[NSAppleEventDescriptor class]])
            [NSException raise:NSInvalidArgumentException format:@"Initial Apple event must be an NSAppleEventDescriptor"];
        [copy setObject:[[custom copy] autorelease] forKey:NSWorkspaceLaunchConfigurationAppleEvent];
    } else if (events.count) {
        NSAppleEventDescriptor *initial=[events objectAtIndex:0];
        /* This address is only the initial descriptor delivered by the explicit
         * URL-based launcher, never a bundle-ID lookup/reselection of a PID. */
        NSString *identifier=[[NSBundle bundleWithURL:app] bundleIdentifier];
        if (identifier.length) [initial setAttributeDescriptor:[NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID
            data:[identifier dataUsingEncoding:NSUTF8StringEncoding]] forKeyword:keyAddressAttr];
        [copy setObject:initial forKey:NSWorkspaceLaunchConfigurationAppleEvent]; next=1;
    }
    NSRunningApplication *original=ops->launch(workspace,app,options,copy,&local);
    if (!original) {
        if (local) { if (error) *error=local; return nil; }
        return failure(error,NSCocoaErrorDomain,NSFileReadUnknownError,@"Application launch failed without a delegated error.");
    }
    pid_t pid=original.processIdentifier;
    NSRunningApplication *selected=pid>0 ? ops->lookup(pid) : nil;
    if (!selected || selected.processIdentifier!=pid || !selected.bundleURL || selected.executableArchitecture<=0)
        return failure(error,NSPOSIXErrorDomain,ESRCH,@"The launched application's populated process identity could not be reacquired; launch may have occurred.");
    NSAppleEventDescriptor *target=[NSAppleEventDescriptor descriptorWithDescriptorType:typeKernelProcessID data:[NSData dataWithBytes:&pid length:sizeof(pid)]];
    for (NSUInteger i=next; i<events.count; i++) {
        NSAppleEventDescriptor *event=[events objectAtIndex:i];
        [event setAttributeDescriptor:target forKeyword:keyAddressAttr];
        OSStatus status=ops->send(event);
        if (status!=noErr) return failure(error,NSOSStatusErrorDomain,status,@"A requested URL event could not be queued; earlier launch or delivery may have occurred.");
    }
    if (files.count && !(options & NSWorkspaceLaunchWithoutAddingToRecents)) {
        local=nil;
        if (!ops->note_recents(files,options,&local)) {
            if (local) { if (error) *error=local; return nil; }
            return failure(error,NSCocoaErrorDomain,NSFileWriteUnknownError,@"Requested-file Recent Documents bookkeeping failed after launch.");
        }
    }
    if (!urls.count) return failure(error,NSCocoaErrorDomain,NSFileReadUnknownError,@"The URL array is empty; application launch or initial-event delivery may have occurred.");
    return selected;
}
NSRunningApplication *__recaulk_objc_workspace_open_urls(id receiver, SEL command, NSArray *urls, NSURL *app,
    NSWorkspaceLaunchOptions options, NSDictionary *configuration, NSError **error) {
    return __recaulk_workspace_open_urls_with_ops(receiver,urls,app,options,configuration,error,NULL);
}
