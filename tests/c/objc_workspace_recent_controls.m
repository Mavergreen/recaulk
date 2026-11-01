/* Research only. Uses the old public launch API and PID-addressed events.
 * Does NOT install/implement the missing method or manufacture empty errors.
 * Approved revision notes ONLY requested fixture files via public APIs. */
#define WORKSPACE_OPTIONS_NO_MAIN 1
#include "objc_workspace_options_reference.m"
#include "objc_workspace_recent_list.h"
#include "objc_workspace_note_recents.h"

static NSAppleEventDescriptor *floorEvent(NSAppleEventDescriptor *target, NSArray *files, NSURL *url, BOOL print) {
    NSAppleEventDescriptor *e = [NSAppleEventDescriptor appleEventWithEventClass:files.count ? kCoreEventClass : kInternetEventClass
        eventID:files.count ? (print ? kAEPrintDocuments : kAEOpenDocuments) : kAEGetURL
        targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    NSAppleEventDescriptor *direct = nil;
    if (files.count) {
        direct = [NSAppleEventDescriptor listDescriptor];
        for (NSURL *file in files)
            [direct insertDescriptor:[NSAppleEventDescriptor descriptorWithDescriptorType:typeFileURL
                data:[file.absoluteString dataUsingEncoding:NSUTF8StringEncoding]] atIndex:direct.numberOfItems+1];
    } else direct = [NSAppleEventDescriptor descriptorWithString:url.absoluteString];
    [e setParamDescriptor:direct forKeyword:keyDirectObject];
    return e;
}
static NSMutableArray *floorEvents(NSArray *urls, NSURL *app, BOOL print) {
    NSAppleEventDescriptor *target = [NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID
        data:[[[NSBundle bundleWithURL:app] bundleIdentifier] dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableArray *files = [NSMutableArray array], *web = [NSMutableArray array], *events = [NSMutableArray array];
    for (NSURL *url in urls) { if (url.isFileURL) [files addObject:url]; else [web addObject:url]; }
    if (files.count) [events addObject:floorEvent(target, files, nil, print)];
    for (NSURL *url in web) [events addObject:floorEvent(target, nil, url, NO)];
    return events;
}
typedef struct {
    OptionsCall call;
    pid_t originalPID;
    NSString *originalBundleURL;
    BOOL finishedAtReturn;
    NSMutableArray *sends;
    BOOL legacyURLAPI;
    BOOL legacyURLResult;
    BOOL recentsResult;
} FloorCall;
static void *floorInvoke(void *argument) {
    FloorCall *f = argument; OptionsCall *c = &f->call;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    c->mainThread = [NSThread isMainThread];
    NSTimeInterval start = [[NSProcessInfo processInfo] systemUptime];
    @try {
        NSMutableArray *events = f->legacyURLAPI ? [NSMutableArray array] : floorEvents(c->urls, c->app, (c->flags & NSWorkspaceLaunchAndPrint) != 0);
        NSMutableDictionary *configuration = [NSMutableDictionary dictionaryWithDictionary:c->configuration];
        if (events.count) [configuration setObject:[events objectAtIndex:0] forKey:NSWorkspaceLaunchConfigurationAppleEvent];
        NSError *error = nil;
        NSRunningApplication *original = [c->workspace launchApplicationAtURL:c->app options:c->flags configuration:configuration error:&error];
        c->error = [error retain];
        f->originalPID = original ? original.processIdentifier : 0;
        f->originalBundleURL = [original.bundleURL.absoluteString copy];
        f->finishedAtReturn = original.finishedLaunching;
        if (original && original.processIdentifier > 0) {
            pid_t pid = original.processIdentifier;
            NSAppleEventDescriptor *target = [NSAppleEventDescriptor descriptorWithDescriptorType:typeKernelProcessID data:[NSData dataWithBytes:&pid length:sizeof(pid)]];
            for (NSUInteger i = 1; i < events.count; i++) {
                NSAppleEventDescriptor *event = [events objectAtIndex:i];
                [event setAttributeDescriptor:target forKeyword:keyAddressAttr];
                OSStatus status = AESendMessage(event.aeDesc, NULL, kAENoReply | kAENeverInteract, kAEDefaultTimeout);
                [f->sends addObject:@(status)];
            }
            if (f->legacyURLAPI) {
                /* Positive CONTROL only: unique owned bundle already launched by
                 * explicit URL. Never a proposed provider PID-selection path. */
                f->legacyURLResult = [c->workspace openURLs:c->urls withAppBundleIdentifier:[[NSBundle bundleWithURL:c->app] bundleIdentifier]
                    options:c->flags additionalEventParamDescriptor:nil launchIdentifiers:NULL];
            }
            /* Only note files after all requested queue operations succeeded. */
            BOOL queued = YES;
            for (NSNumber *status in f->sends) queued &= status.intValue == 0;
            NSError *noteError = nil;
            f->recentsResult = f->legacyURLAPI || (queued && floorNoteRecentFiles(c->urls, c->flags, &noteError));
            if (noteError) { [c->error release]; c->error = [noteError retain]; }
            NSRunningApplication *fresh = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            c->returned = [(fresh ?: original) retain];
        }
    } @catch (NSException *e) { c->exception = [@{ @"name": e.name, @"reason": e.reason ?: @"" } retain]; }
    c->duration = [[NSProcessInfo processInfo] systemUptime] - start;
    [pool drain]; return NULL;
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new]; installWorkspaceSignals();
    if (argc != 4) return 2;
    NSString *name = [NSString stringWithUTF8String:argv[1]];
    NSURL *app = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
    NSString *root = [NSString stringWithUTF8String:argv[3]], *events = [root stringByAppendingPathComponent:@"events"];
    if (!fixturePrerequisites(app, root, events) || class_getInstanceMethod([NSWorkspace class], @selector(openURLs:withApplicationAtURL:options:configuration:error:))) return 1;
    NSArray *known = [@"default browser-default files legacy-open-files legacy-print interleaved print hide without-activation without-recents empty async worker worker-files" componentsSeparatedByString:@" "];
    if (![known containsObject:name]) return 1;
    NSMutableArray *failures = [NSMutableArray array];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:name, @"case",
        @"public 10.9 primitive control; NOT native missing method, provider or equivalence verdict", @"scope",
        @"known private path AND literal file-reference matching; unknown references unresolved", @"recents_reader", nil];
    FloorCall f; memset(&f, 0, sizeof(f)); f.sends = [NSMutableArray array];
    BOOL fileCase = [@[@"files", @"legacy-open-files", @"legacy-print", @"interleaved", @"print", @"without-recents", @"worker-files"] containsObject:name];
    NSURL *fileOne = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"one.txt"]];
    NSURL *fileTwo = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"two.txt"]];
    NSArray *files = fileCase ? @[fileOne,fileTwo] : @[];
    @try {
        for (NSURL *file in files) if (!optionsFile(file.path)) [NSException raise:@"ControlError" format:@"exclusive fixture file creation"];
        NSString *nonce = [[NSProcessInfo processInfo] globallyUniqueString];
        NSURL *one = [NSURL URLWithString:[@"https://floor-options.invalid/one/" stringByAppendingString:nonce]];
        NSURL *two = [NSURL URLWithString:[@"https://floor-options.invalid/two/" stringByAppendingString:nonce]];
        NSArray *urls = fileCase ? files : @[one];
        if ([name isEqual:@"interleaved"]) urls = @[fileOne,one,fileTwo,two];
        if ([name isEqual:@"empty"]) urls = @[];
        NSWorkspaceLaunchOptions flags = NSWorkspaceLaunchWithoutActivation;
        if ([name isEqual:@"default"]) flags = NSWorkspaceLaunchDefault;
        /* The newer SDK/Rust Default omits the obsolete Classic-startup bit. */
        if ([name isEqual:@"browser-default"]) flags = NSWorkspaceLaunchAsync;
        if ([name isEqual:@"print"] || [name isEqual:@"legacy-print"]) flags |= NSWorkspaceLaunchAndPrint;
        if ([name isEqual:@"hide"]) flags |= NSWorkspaceLaunchAndHide;
        if ([name isEqual:@"without-recents"]) flags |= NSWorkspaceLaunchWithoutAddingToRecents;
        if ([name isEqual:@"async"] || [name hasPrefix:@"worker"]) flags |= NSWorkspaceLaunchAsync;
        [result setObject:@(flags) forKey:@"options"];
        [result setObject:floorRecents(app, files) forKey:@"recents_before"];
        f.legacyURLAPI = [name hasPrefix:@"legacy-"];
        f.call.workspace = [NSWorkspace sharedWorkspace]; f.call.urls = urls; f.call.app = app; f.call.flags = flags; f.call.configuration = @{};
        if ([name hasPrefix:@"worker"]) {
            pthread_t thread; int rc = pthread_create(&thread, NULL, floorInvoke, &f);
            if (rc) [NSException raise:@"ControlError" format:@"pthread_create %d", rc];
            rc = pthread_join(thread, NULL);
            if (rc) [NSException raise:@"ControlError" format:@"pthread_join %d", rc];
        } else floorInvoke(&f);
        [result setObject:@(f.originalPID) forKey:@"original_pid"];
        [result setObject:f.originalBundleURL ?: (id)[NSNull null] forKey:@"original_bundle_url"];
        [result setObject:@(f.finishedAtReturn) forKey:@"original_finished_at_return"];
        [result setObject:@(f.call.returned ? f.call.returned.processIdentifier : 0) forKey:@"returned_pid"];
        [result setObject:f.call.returned.bundleURL.absoluteString ?: (id)[NSNull null] forKey:@"reacquired_bundle_url"];
        [result setObject:@(f.call.mainThread) forKey:@"call_on_main_thread"];
        [result setObject:@(f.call.duration) forKey:@"call_duration_seconds"];
        [result setObject:f.call.error.domain ?: (id)[NSNull null] forKey:@"error_domain"];
        [result setObject:f.call.error ? @(f.call.error.code) : (id)[NSNull null] forKey:@"error_code"];
        [result setObject:f.sends forKey:@"subsequent_send_statuses"];
        [result setObject:@(f.recentsResult) forKey:@"recents_bookkeeping_completed"];
        workspaceCheck(f.recentsResult, @"requested-file Recents operation completed or intentionally suppressed", failures);
        if (f.legacyURLAPI) {
            [result setObject:@(f.legacyURLResult) forKey:@"legacy_open_urls_return"];
            workspaceCheck(f.legacyURLResult, @"old URL-opening positive control succeeded", failures);
        }
        if (f.call.exception) [result setObject:f.call.exception forKey:@"exception"];
        workspaceCheck(!f.call.exception, @"public primitive did not throw", failures);
        workspaceCheck(owned(f.call.returned, app), @"reacquired exact private app identity", failures);
        for (NSNumber *status in f.sends) workspaceCheck(status.intValue == 0, @"subsequent send succeeded (not delivery proof)", failures);
        if (f.originalPID > 0) {
            NSDictionary *snapshot = optionsSnapshot(events, f.originalPID, urls, (flags & NSWorkspaceLaunchAndPrint) != 0, [name isEqual:@"hide"]);
            [result setObject:snapshot forKey:@"evidence_observation"];
            workspaceCheck([[snapshot objectForKey:@"requirements_observed"] boolValue], @"all requested external payloads observed at system-selected PID", failures);
            if ([name isEqual:@"hide"]) {
                NSTimeInterval end = [[NSProcessInfo processInfo] systemUptime] + 1;
                while (!f.call.returned.hidden && [[NSProcessInfo processInfo] systemUptime] < end)
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
                [result setObject:@(f.call.returned.hidden) forKey:@"final_hidden"];
                workspaceCheck(f.call.returned.hidden, @"private app hidden after finish", failures);
            }
            if ([name isEqual:@"without-activation"]) workspaceCheck([[NSWorkspace sharedWorkspace] frontmostApplication].processIdentifier != f.originalPID, @"private app not frontmost at observation", failures);
        }
    } @catch (NSException *e) { [result setObject:e.reason ?: e.name forKey:@"harness_exception"]; [failures addObject:@"harness failure"]; }
    @finally {
        NSMutableArray *apps = [NSMutableArray array];
        NSTimeInterval end = [[NSProcessInfo processInfo] systemUptime] + 3;
        do {
            for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications]) if (owned(a, app) && ![apps containsObject:a]) [apps addObject:a];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        } while ([[NSProcessInfo processInfo] systemUptime] < end && !workspaceInterrupted);
        NSDictionary *after = floorRecents(app, files);
        [result setObject:after forKey:@"recents_after"];
        if (fileCase) {
            NSDictionary *b = [[result objectForKey:@"recents_before"] objectForKey:@"documents"];
            NSDictionary *a = [after objectForKey:@"documents"];
            BOOL readable = [[b objectForKey:@"available"] boolValue] && [[a objectForKey:@"available"] boolValue];
            workspaceCheck(readable, @"document Recents list readable (no settings changed)", failures);
            if (f.call.flags & NSWorkspaceLaunchWithoutAddingToRecents) {
                workspaceCheck([[a objectForKey:@"matching_private_items"] unsignedIntegerValue] == 0 &&
                    [[a objectForKey:@"snapshot_seed"] isEqual:[b objectForKey:@"snapshot_seed"]],
                    @"WithoutAddingToRecents leaves document history unchanged in checked interval", failures);
            } else {
                NSInteger limit = [[a objectForKey:@"items_limit"] integerValue];
                workspaceCheck(limit > 0, @"positive Recents control requires observable nonzero system limit; never force settings", failures);
                workspaceCheck([[a objectForKey:@"matching_private_items"] unsignedIntegerValue] == files.count,
                    @"all requested private documents appear in Recents", failures);
                workspaceCheck([[a objectForKey:@"item_count"] integerValue] <= limit,
                    @"normal system Recent Documents limit preserved without explicit removal", failures);
            }
        }
        BOOL cleaned = YES;
        for (NSRunningApplication *a in apps) if (owned(a, app)) {
            [a terminate]; end = [[NSProcessInfo processInfo] systemUptime] + 3;
            while (!a.terminated && [[NSProcessInfo processInfo] systemUptime] < end) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            if (!a.terminated && owned(a, app)) [a forceTerminate];
            end = [[NSProcessInfo processInfo] systemUptime] + 3;
            while (!a.terminated && [[NSProcessInfo processInfo] systemUptime] < end) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            cleaned &= a.terminated;
        }
        [result setObject:@(cleaned) forKey:@"cleanup_completed"];
        workspaceCheck(cleaned, @"private fixture cleanup completed", failures);
        [f.call.returned release]; [f.call.error release]; [f.call.exception release]; [f.originalBundleURL release];
    }
    if (workspaceInterrupted) [failures addObject:@"interrupted, evidence incomplete"];
    [result setObject:failures forKey:@"failures"];
    [result setObject:@(class_getInstanceMethod([NSWorkspace class], @selector(openURLs:withApplicationAtURL:options:configuration:error:)) != NULL) forKey:@"target_method_present_after"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    BOOL written = data && fwrite(data.bytes, 1, data.length, stdout) == data.length;
    putchar('\n'); BOOL ok = written && !failures.count;
    [pool drain]; return ok ? 0 : 1;
}
