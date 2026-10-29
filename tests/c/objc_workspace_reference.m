/* Native contract oracle only. Never activates Recaulk or replaces a method.
 * Contracts: pinned NSWorkspace.h configuration comments and Apple's DocC
 * open(_:withApplicationAt:options:configuration:) entry. Undocumented cases
 * deliberately report observed-only, even when the native call succeeds. */
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#include <unistd.h>

#if !defined(MAC_OS_X_VERSION_10_10) || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_10
/* platform: declaration only for the floor SDK; runtime absence is checked before either call. */
@interface NSWorkspace (WorkspaceReferenceDeclaration)
- (NSRunningApplication *)openURLs:(NSArray *)urls
             withApplicationAtURL:(NSURL *)applicationURL
                          options:(NSWorkspaceLaunchOptions)options
                    configuration:(NSDictionary *)configuration
                            error:(NSError **)error;
@end
#endif

static NSString *hostArch(void) {
#if defined(__arm64__)
    return @"arm64";
#else
    return @"x86_64";
#endif
}
static NSArray *records(NSString *dir, pid_t pid) {
    NSString *s = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.jsonl", pid]] encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in [s componentsSeparatedByString:@"\n"]) {
        if (![line length]) continue;
        id r = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        if (r) [out addObject:r];
    }
    return out;
}
static BOOL contains(NSArray *rs, NSString *kind, NSString *url) {
    for (NSDictionary *r in rs) if ([[r objectForKey:@"kind"] isEqual:kind] && (!url || [[r objectForKey:@"urls"] containsObject:url])) return YES;
    return NO;
}
static NSArray *waitRecords(NSString *dir, pid_t pid, NSArray *urls, NSString *kind) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12];
    NSArray *rs = nil;
    do {
        rs = records(dir, pid);
        BOOL ready = contains(rs, @"startup", nil);
        if (kind) ready &= contains(rs, kind, nil);
        for (NSURL *u in urls) ready &= contains(rs, @"open", [u absoluteString]);
        if (ready) break;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    } while ([deadline timeIntervalSinceNow] > 0);
    return rs;
}
static BOOL owned(NSRunningApplication *app, NSURL *url) {
    return app && [[[app bundleURL] URLByResolvingSymlinksInPath] isEqual:[url URLByResolvingSymlinksInPath]];
}
static void workspaceCheck(BOOL ok, NSString *message, NSMutableArray *failures) {
    if (!ok) [failures addObject:message];
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if (argc != 4) { fprintf(stderr, "usage: reference CASE APP_URL REPORT_DIR\n"); return 1; }
    NSString *c = [NSString stringWithUTF8String:argv[1]];
    NSURL *appURL = [NSURL URLWithString:[NSString stringWithUTF8String:argv[2]]];
    if (![appURL isFileURL]) appURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
    NSString *report = [NSString stringWithUTF8String:argv[3]];
    NSString *events = [report stringByAppendingPathComponent:@"events"];
    SEL sel = @selector(openURLs:withApplicationAtURL:options:configuration:error:);
    Method method = class_getInstanceMethod([NSWorkspace class], sel);
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:c, @"case", [[NSProcessInfo processInfo] operatingSystemVersionString], @"os", hostArch(), @"architecture", nil];
    NSMutableArray *failures = [NSMutableArray array];
    NSMutableArray *calls = [NSMutableArray array];
    NSMutableArray *cleanup = [NSMutableArray array];
    [result setObject:calls forKey:@"calls"];
    int rc = 0;
    NSArray *known = [@"stopped reused multiple mixed new-instance startup reuse-configuration without-activation custom-event invalid-app nil-error ownership empty conflicting-event unknown-key impossible-architecture asynchronous architecture" componentsSeparatedByString:@" "];
    if (![known containsObject:c]) {
        [failures addObject:@"unknown case"]; rc = 1; goto finish;
    }
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:[[appURL path] stringByAppendingPathComponent:@"Contents/MacOS/WorkspaceProbe"]] || ![[NSFileManager defaultManager] fileExistsAtPath:events]) {
        [failures addObject:@"missing fixture/report prerequisites"]; rc = 1; goto finish;
    }
    if (!method) { [result setObject:@"system-method-absent" forKey:@"disposition"]; rc = 77; goto write; }
    [result setObject:[NSString stringWithUTF8String:method_getTypeEncoding(method)] forKey:@"method_encoding"];
    @try {
        BOOL reuse = [@[@"reused", @"new-instance", @"reuse-configuration"] containsObject:c];
        BOOL observation = [@[@"empty", @"conflicting-event", @"unknown-key", @"impossible-architecture", @"asynchronous"] containsObject:c];
        [result setObject:[NSNumber numberWithBool:observation] forKey:@"observation_only"];
        NSURL *one = [NSURL URLWithString:@"https://workspace-probe.invalid/sentinel-one"];
        NSURL *two = [NSURL URLWithString:@"https://workspace-probe.invalid/sentinel-two"];
        NSMutableArray *urls = [NSMutableArray arrayWithObject:one];
        if ([c isEqual:@"multiple"]) [urls addObject:two];
        if ([c isEqual:@"mixed"]) {
            NSString *file = [report stringByAppendingPathComponent:@"sentinel.txt"];
            workspaceCheck([@"fixture" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"write mixed file", failures);
            [urls addObject:[NSURL fileURLWithPath:file]];
        }
        if ([c isEqual:@"empty"] || [c isEqual:@"custom-event"]) [urls removeAllObjects];
        NSMutableDictionary *config = [NSMutableDictionary dictionaryWithObjectsAndKeys:@[@"--workspace-sentinel", @"argv exact value"], NSWorkspaceLaunchConfigurationArguments, @{@"WORKSPACE_PROBE_SENTINEL": @"environment exact value"}, NSWorkspaceLaunchConfigurationEnvironment, nil];
        NSRunningApplication *first = nil;
        if (reuse) {
            NSError *e = nil;
            first = [[NSWorkspace sharedWorkspace] openURLs:@[two] withApplicationAtURL:appURL options:NSWorkspaceLaunchWithoutActivation configuration:config error:&e];
            if (owned(first, appURL)) [cleanup addObject:first];
            NSArray *rs = waitRecords(events, [first processIdentifier], @[two], nil);
            workspaceCheck(owned(first, appURL) && contains(rs, @"open", [two absoluteString]), @"seed instance received URL", failures);
            [result setObject:rs forKey:@"seed_evidence"];
            [result setObject:@([first processIdentifier]) forKey:@"seed_pid"];
            [config setObject:@[@"--must-not-reach-existing-process"] forKey:NSWorkspaceLaunchConfigurationArguments];
            [config setObject:@{@"WORKSPACE_PROBE_SENTINEL": @"must not replace startup environment"} forKey:NSWorkspaceLaunchConfigurationEnvironment];
        }
        if ([c isEqual:@"custom-event"] || [c isEqual:@"conflicting-event"]) {
            NSAppleEventDescriptor *ev = [NSAppleEventDescriptor appleEventWithEventClass:'WPrb' eventID:'ping' targetDescriptor:[NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID data:[[[NSBundle bundleWithURL:appURL] bundleIdentifier] dataUsingEncoding:NSUTF8StringEncoding]] returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
            [ev setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"custom sentinel"] forKeyword:keyDirectObject];
            [config setObject:ev forKey:NSWorkspaceLaunchConfigurationAppleEvent];
        }
        if ([c isEqual:@"unknown-key"]) [config setObject:@"sentinel" forKey:@"org.mavergreen.unknown-configuration-key"];
        if ([c isEqual:@"architecture"] || [c isEqual:@"impossible-architecture"]) {
#if defined(__arm64__)
            NSNumber *arch = @(0x0100000c); /* CPU_TYPE_ARM64, same NSNumber contract as NSBundleExecutableArchitecture */
#else
            NSNumber *arch = @(NSBundleExecutableArchitectureX86_64);
#endif
            if ([c isEqual:@"impossible-architecture"]) arch = @(0x7fffffff);
            [config setObject:arch forKey:NSWorkspaceLaunchConfigurationArchitecture];
        }
        NSWorkspaceLaunchOptions flags = NSWorkspaceLaunchWithoutActivation;
        if ([c isEqual:@"new-instance"]) flags |= NSWorkspaceLaunchNewInstance;
        if ([c isEqual:@"asynchronous"]) flags |= NSWorkspaceLaunchAsync;
        NSURL *target = [c isEqual:@"invalid-app"] ? [NSURL fileURLWithPath:[report stringByAppendingPathComponent:@"DoesNotExist.app"]] : appURL;
        NSRunningApplication *front = [NSWorkspace sharedWorkspace].frontmostApplication;
        pid_t frontPID = [front processIdentifier];
        NSAutoreleasePool *inner = [NSAutoreleasePool new];
        NSError *error = nil;
        NSRunningApplication *returned = [[[NSWorkspace sharedWorkspace] openURLs:urls withApplicationAtURL:target options:flags configuration:config error:[c isEqual:@"nil-error"] ? NULL : &error] retain];
        [error retain];
        NSDictionary *immediate = @{ @"finished_launching": @([returned isFinishedLaunching]), @"terminated": @([returned isTerminated]) };
        [immediate retain];
        [inner drain]; /* normal +0 return/out-error: explicit retains must survive this boundary */
        if (owned(returned, appURL) && ![cleanup containsObject:returned]) [cleanup addObject:returned];
        pid_t pid = [returned processIdentifier];
        NSMutableDictionary *call = [NSMutableDictionary dictionaryWithObjectsAndKeys:@(pid), @"returned_pid", [returned.bundleURL absoluteString] ?: (id)[NSNull null], @"returned_bundle_url", error.domain ?: (id)[NSNull null], @"error_domain", error ? @(error.code) : (id)[NSNull null], @"error_code", immediate, @"immediate_state", @(flags), @"options", nil];
        [calls addObject:call];
        NSArray *expected = observation ? @[] : urls;
        NSArray *rs = returned ? waitRecords(events, pid, expected, [c isEqual:@"custom-event"] ? @"custom" : nil) : @[];
        [call setObject:rs forKey:@"evidence"];
        if ([c isEqual:@"invalid-app"]) workspaceCheck(!returned && error && [error.domain length], @"invalid app returns nil and usable NSError across pool boundary", failures);
        else if (!observation) {
            workspaceCheck(owned(returned, appURL), @"returned application is fixture bundle", failures);
            workspaceCheck(pid > 0 && contains(rs, @"startup", nil), @"returned PID has startup evidence", failures);
            for (NSURL *u in urls) workspaceCheck(contains(rs, @"open", u.absoluteString), @"returned PID received exact URL", failures);
            if (reuse) workspaceCheck([c isEqual:@"new-instance"] ? pid != first.processIdentifier : pid == first.processIdentifier, @"reuse/new-instance PID relationship", failures);
            for (NSDictionary *r in rs) if ([[r objectForKey:@"kind"] isEqual:@"startup"]) {
                BOOL newInstance = [c isEqual:@"new-instance"];
                NSArray *args = [r objectForKey:@"argv"];
                workspaceCheck(newInstance ? [args containsObject:@"--must-not-reach-existing-process"] : ([args containsObject:@"--workspace-sentinel"] && [args containsObject:@"argv exact value"]), @"exact sentinel startup arguments", failures);
                workspaceCheck([[r objectForKey:@"sentinel"] isEqual:newInstance ? @"must not replace startup environment" : @"environment exact value"], @"exact sentinel startup environment (unchanged on reuse)", failures);
                if ([c isEqual:@"architecture"]) workspaceCheck([[r objectForKey:@"architecture"] isEqual:hostArch()], @"requested host architecture actually executed", failures);
            }
            if ([c isEqual:@"custom-event"]) workspaceCheck(contains(rs, @"custom", nil), @"custom initial Apple event delivered", failures);
            if ([c isEqual:@"without-activation"]) workspaceCheck([[NSWorkspace sharedWorkspace].frontmostApplication processIdentifier] != pid && frontPID != pid, @"without-activation does not activate fixture", failures);
        }
        [immediate release]; [returned release]; [error release];
        /* Capture every fixture-owned PID, including side effects of failing calls.
         * Bundle identity, not process name or untrusted log PID, authorizes termination. */
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        NSMutableArray *sideEffects = [NSMutableArray array];
        for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications]) if (owned(a, appURL)) {
            if (![cleanup containsObject:a]) [cleanup addObject:a];
            [sideEffects addObject:@{@"pid": @(a.processIdentifier), @"records": records(events, a.processIdentifier)}];
        }
        [result setObject:sideEffects forKey:@"side_effects"];
        if ([c isEqual:@"architecture"]) [result setObject:@"dual-slice capability not measured" forKey:@"missing_observation"];
    } @catch (NSException *e) {
        [result setObject:@{@"name": e.name, @"reason": e.reason ?: @""} forKey:@"exception"];
        if (![[result objectForKey:@"observation_only"] boolValue]) [failures addObject:@"native API raised exception"];
        NSMutableArray *sideEffects = [NSMutableArray array];
        for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications]) if (owned(a, appURL)) {
            if (![cleanup containsObject:a]) [cleanup addObject:a];
            [sideEffects addObject:@{@"pid": @(a.processIdentifier), @"records": records(events, a.processIdentifier)}];
        }
        [result setObject:sideEffects forKey:@"side_effects"];
    }
finish:
    for (NSRunningApplication *a in cleanup) if (owned(a, appURL)) {
        [a terminate];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!a.terminated && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!a.terminated && owned(a, appURL)) [a forceTerminate];
    }
    [result setObject:failures forKey:@"failures"];
    rc = [failures count] ? 1 : rc;
    [result setObject:rc ? @"failed" : ([[result objectForKey:@"observation_only"] boolValue] ? @"observed-only" : @"passed") forKey:@"disposition"];
write:
    {
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        if (!data || ![data writeToFile:[report stringByAppendingPathComponent:@"controller.json"] atomically:YES]) rc = 1;
        printf("%s: %s\n", c.UTF8String, [[result objectForKey:@"disposition"] UTF8String]);
    }
    [pool drain];
    return rc;
}
