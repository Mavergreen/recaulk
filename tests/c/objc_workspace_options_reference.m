/* Additional native measurements only: never registers a method or requests consent.
 * Reuse the unchanged baseline's fixture identity, bounded JSONL reader and signals.
 * This is NOT the provider, an all-flags oracle or independent acceptance. */
#define main workspaceOriginalReferenceMain
#include "objc_workspace_reference.m"
#undef main
#include <pthread.h>

static BOOL optionsWrite(int fd, NSData *data) {
    if (!data) return NO;
    const unsigned char *bytes = data.bytes;
    NSUInteger left = data.length;
    while (left) {
        ssize_t n = write(fd, bytes, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        bytes += n; left -= n;
    }
    return YES;
}
/* Unlike the original open-only waiter, AndPrint must wait for EVERY file,
 * not return after the first print callback and race a second batch. */
static NSDictionary *optionsSnapshot(NSString *dir, pid_t pid, NSArray *urls, BOOL print, BOOL finished) {
    NSTimeInterval deadline = [[NSProcessInfo processInfo] systemUptime] + 12;
    for (;;) {
        NSDictionary *snapshot = recordSnapshot(dir, pid);
        NSArray *rs = [snapshot objectForKey:@"records"];
        BOOL ready = contains(rs, @"startup", nil) && [[snapshot objectForKey:@"incomplete_tail_bytes"] unsignedIntegerValue] == 0;
        if (finished) ready &= contains(rs, @"finished-launching", nil);
        for (NSURL *url in urls) ready &= contains(rs, print ? @"print" : @"open", url.absoluteString);
        BOOL expired = [[NSProcessInfo processInfo] systemUptime] >= deadline;
        if (ready || expired || workspaceInterrupted) {
            NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:snapshot];
            [out addEntriesFromDictionary:@{ @"requirements_observed": @(ready), @"deadline_expired": @(!ready && expired),
                @"deadline_seconds": @12, @"interrupted": @(workspaceInterrupted != 0) }];
            return out;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}
static BOOL optionsFile(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) return NO;
    BOOL ok = optionsWrite(fd, [@"private workspace options fixture\n" dataUsingEncoding:NSUTF8StringEncoding]);
    return close(fd) == 0 && ok;
}
/* Only counts matching private fixture URLs. No names/URLs from unrelated user
 * history are emitted; resolution never mounts volumes or displays user UI.
 * Missing/partly unresolved lists cannot establish recents suppression. */
static NSDictionary *optionsRecentList(CFStringRef kind, NSURL *app, NSArray *files) {
    LSSharedFileListRef list = LSSharedFileListCreate(kCFAllocatorDefault, kind, NULL);
    if (!list) return @{ @"available": @NO };
    CFArrayRef snapshot = LSSharedFileListCopySnapshot(list, NULL);
    /* Resolve only our known controlled paths, never arbitrary recent-item
     * paths (which could otherwise trigger filesystem/automount side effects). */
    NSMutableArray *expected = [NSMutableArray arrayWithObjects:app, [app URLByResolvingSymlinksInPath], nil];
    for (NSURL *file in files) { [expected addObject:file]; [expected addObject:[file URLByResolvingSymlinksInPath]]; }
    NSUInteger matches = 0, unresolved = 0;
    if (snapshot) {
        for (CFIndex i = 0; i < CFArrayGetCount(snapshot); i++) {
            CFURLRef url = NULL;
            OSStatus s = LSSharedFileListItemResolve((LSSharedFileListItemRef)CFArrayGetValueAtIndex(snapshot, i),
                kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes, &url, NULL);
            if (s || !url) unresolved++;
            else {
                NSURL *candidate = (NSURL *)url;
                if ([candidate isFileReferenceURL]) unresolved++;
                else if ([expected containsObject:candidate]) matches++;
            }
            if (url) CFRelease(url);
        }
        CFRelease(snapshot);
    }
    CFRelease(list);
    return @{ @"available": @(snapshot != NULL), @"matching_private_items": @(matches), @"unresolved_item_count": @(unresolved) };
}
static NSDictionary *optionsRecents(NSURL *app, NSArray *files) {
    return @{ @"applications": optionsRecentList(kLSSharedFileListRecentApplicationItems, app, files),
              @"documents": optionsRecentList(kLSSharedFileListRecentDocumentItems, app, files) };
}

typedef struct {
    NSWorkspace *workspace;
    NSArray *urls;
    NSURL *app;
    NSWorkspaceLaunchOptions flags;
    NSDictionary *configuration;
    NSRunningApplication *returned;
    NSError *error;
    NSDictionary *exception;
    BOOL mainThread;
    NSTimeInterval duration;
} OptionsCall;
static void *optionsInvoke(void *argument) {
    OptionsCall *call = argument;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    call->mainThread = [NSThread isMainThread];
    NSTimeInterval started = [[NSProcessInfo processInfo] systemUptime];
    @try {
        NSError *error = nil;
        call->returned = [[call->workspace openURLs:call->urls withApplicationAtURL:call->app
            options:call->flags configuration:call->configuration error:&error] retain];
        call->error = [error retain];
    } @catch (NSException *exception) {
        call->exception = [@{ @"name": exception.name, @"reason": exception.reason ?: @"" } retain];
    }
    call->duration = [[NSProcessInfo processInfo] systemUptime] - started;
    [pool drain];
    return NULL;
}

#ifndef WORKSPACE_OPTIONS_NO_MAIN
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if (argc != 4) { fprintf(stderr, "usage: options-reference CASE APP_URL REPORT_DIR\n"); [pool drain]; return 1; }
    installWorkspaceSignals();
    NSString *c = [NSString stringWithUTF8String:argv[1]];
    NSString *input = [NSString stringWithUTF8String:argv[2]];
    NSURL *app = [input isAbsolutePath] ? [NSURL fileURLWithPath:input] : [NSURL URLWithString:input];
    NSString *report = [NSString stringWithUTF8String:argv[3]];
    if (!safeFixturePath(report)) { fprintf(stderr, "unsafe report directory\n"); [pool drain]; return 1; }
    int dir = open(report.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    struct stat st;
    if (dir < 0 || fstat(dir, &st) || !S_ISDIR(st.st_mode) || st.st_uid != geteuid() || (st.st_mode & 077) || fchdir(dir)) {
        if (dir >= 0) close(dir);
        fprintf(stderr, "report directory must be private and owned\n"); [pool drain]; return 1;
    }
    int output = open("controller.json", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    close(dir);
    if (output < 0) { fprintf(stderr, "refusing existing or linked output\n"); [pool drain]; return 1; }
    NSMutableArray *failures = [NSMutableArray array];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        c, @"case", hostArch(), @"architecture", [[NSProcessInfo processInfo] operatingSystemVersionString], @"os",
        @"additional native measurements; not provider acceptance", @"scope", nil];
    NSString *events = [report stringByAppendingPathComponent:@"events"];
    NSArray *known = [@"default files interleaved print hide without-activation without-recents empty async worker nil-urls nil-configuration non-url-element relative-url" componentsSeparatedByString:@" "];
    BOOL invalidShapeObservation = [@[@"empty", @"nil-urls", @"nil-configuration", @"non-url-element", @"relative-url"] containsObject:c];
    BOOL observation = invalidShapeObservation || [c isEqual:@"without-recents"];
    [result setObject:@(observation) forKey:@"observation_only"];
    [result setObject:@"valid nonempty cases assert fixture identity and complete external payload delivery; grouping/async timing/recents are separate observations" forKey:@"assertion_scope"];
    int rc = 0;
    if (![known containsObject:c]) { [failures addObject:@"unknown case"]; goto finish; }
    if (!fixturePrerequisites(app, report, events)) { [failures addObject:@"fixture/report prerequisite mismatch"]; goto finish; }
    BOOL needsFiles = [@[@"files", @"interleaved", @"print", @"without-recents"] containsObject:c];
    if (needsFiles) {
        for (NSString *name in @[@"one.txt", @"two.txt"]) {
            if (!lstat(name.fileSystemRepresentation, &st) || errno != ENOENT) {
                [failures addObject:@"sentinel already exists or cannot be inspected"]; goto finish;
            }
        }
    }
    SEL selector = @selector(openURLs:withApplicationAtURL:options:configuration:error:);
    Method method = class_getInstanceMethod([NSWorkspace class], selector);
    if (!method) { [result setObject:@"system-method-absent" forKey:@"disposition"]; rc = 77; goto writeReport; }
    [result setObject:[NSString stringWithUTF8String:method_getTypeEncoding(method)] forKey:@"method_encoding"];
    OptionsCall call;
    memset(&call, 0, sizeof(call));
    @try {
        NSString *nonce = [[NSProcessInfo processInfo] globallyUniqueString];
        [result setObject:nonce forKey:@"case_nonce"];
        NSURL *one = [NSURL URLWithString:[@"https://workspace-options.invalid/one/" stringByAppendingString:nonce]];
        NSURL *two = [NSURL URLWithString:[@"https://workspace-options.invalid/two/" stringByAppendingString:nonce]];
        NSURL *fileOne = [NSURL fileURLWithPath:[report stringByAppendingPathComponent:@"one.txt"]];
        NSURL *fileTwo = [NSURL fileURLWithPath:[report stringByAppendingPathComponent:@"two.txt"]];
        if (needsFiles && (!optionsFile(fileOne.path) || !optionsFile(fileTwo.path)))
            [NSException raise:@"WorkspaceOptionsEvidenceError" format:@"exclusive fixture file creation failed"];
        NSArray *files = needsFiles ? @[fileOne, fileTwo] : @[];
        NSArray *urls = @[one];
        if ([c isEqual:@"files"] || [c isEqual:@"print"] || [c isEqual:@"without-recents"]) urls = files;
        if ([c isEqual:@"interleaved"]) urls = @[fileOne, one, fileTwo, two];
        if ([c isEqual:@"empty"]) urls = @[];
        if ([c isEqual:@"nil-urls"]) urls = nil;
        if ([c isEqual:@"non-url-element"]) urls = (id)@[@"not an NSURL"];
        if ([c isEqual:@"relative-url"]) urls = @[[NSURL URLWithString:@"relative/item"]];
        NSWorkspaceLaunchOptions flags = NSWorkspaceLaunchWithoutActivation;
        if ([c isEqual:@"default"]) flags = NSWorkspaceLaunchDefault;
        if ([c isEqual:@"print"]) flags |= NSWorkspaceLaunchAndPrint;
        if ([c isEqual:@"hide"]) flags |= NSWorkspaceLaunchAndHide;
        if ([c isEqual:@"without-recents"]) flags |= NSWorkspaceLaunchWithoutAddingToRecents;
        if ([c isEqual:@"async"] || [c isEqual:@"worker"]) flags |= NSWorkspaceLaunchAsync;
        [result setObject:@(flags) forKey:@"options"];
        [result setObject:[urls description] ?: (id)[NSNull null] forKey:@"requested_urls"];
        /* Recents input is restricted to the fixture; only matching counts leave
         * memory. A before/after zero is a bounded observation, not a guarantee. */
        if ([c isEqual:@"default"] || [c isEqual:@"files"] || [c isEqual:@"without-recents"])
            [result setObject:optionsRecents(app, files) forKey:@"recents_before"];
        call.workspace = [NSWorkspace sharedWorkspace];
        call.urls = urls;
        call.app = app; /* Never let malformed target tests select a real default handler. */
        call.flags = flags;
        call.configuration = [c isEqual:@"nil-configuration"] ? nil : @{};
        if ([c isEqual:@"worker"]) {
            pthread_t thread;
            int status = pthread_create(&thread, NULL, optionsInvoke, &call);
            if (status) [NSException raise:@"WorkspaceOptionsEvidenceError" format:@"pthread_create: %d", status];
            /* No caller run loop is pumped while the invocation runs. This is
             * not a bounded-call-latency guarantee; OS invocation may block. */
            status = pthread_join(thread, NULL);
            if (status) [NSException raise:@"WorkspaceOptionsEvidenceError" format:@"pthread_join: %d", status];
        } else optionsInvoke(&call);
        [result setObject:@(call.mainThread) forKey:@"call_on_main_thread"];
        [result setObject:@(call.duration) forKey:@"call_duration_seconds"];
        [result setObject:@(call.returned ? call.returned.processIdentifier : 0) forKey:@"returned_pid"];
        [result setObject:call.returned.bundleURL.absoluteString ?: (id)[NSNull null] forKey:@"bundle_url_at_return"];
        [result setObject:@(call.returned.finishedLaunching) forKey:@"finished_at_return"];
        [result setObject:call.error.domain ?: (id)[NSNull null] forKey:@"error_domain"];
        [result setObject:call.error ? @(call.error.code) : (id)[NSNull null] forKey:@"error_code"];
        if (call.exception) [result setObject:call.exception forKey:@"native_exception"];
        if (!invalidShapeObservation) {
            workspaceCheck(call.exception == nil, @"well-typed invocation must not throw", failures);
            workspaceCheck(owned(call.returned, app), @"returned application identity matches the explicit fixture", failures);
            workspaceCheck(call.mainThread != [c isEqual:@"worker"], @"requested calling thread was actually used", failures);
        }
        if (call.returned && call.returned.processIdentifier > 0 && !call.exception) {
            NSArray *expected = invalidShapeObservation ? @[] : urls;
            NSDictionary *snapshot = optionsSnapshot(events, call.returned.processIdentifier, expected,
                [c isEqual:@"print"], [c isEqual:@"hide"]);
            [result setObject:snapshot forKey:@"evidence_observation"];
            /* Missing startup/partial JSONL is a measurement failure even in an
             * observed-only case; successful return alone is never acceptance. */
            workspaceCheck([[snapshot objectForKey:@"requirements_observed"] boolValue], @"complete returned-PID evidence observed before deadline", failures);
            NSArray *rs = [snapshot objectForKey:@"records"];
            NSMutableArray *groups = [NSMutableArray array];
            for (NSDictionary *record in rs) {
                if ([[record objectForKey:@"event_id"] unsignedIntValue] == kAEOpenDocuments ||
                    [[record objectForKey:@"event_id"] unsignedIntValue] == kAEPrintDocuments)
                    [groups addObject:[record objectForKey:@"urls"]];
            }
            [result setObject:groups forKey:@"observed_file_event_groups"];
            if ([c isEqual:@"print"]) {
                for (NSURL *file in files) workspaceCheck(contains(rs, @"print", file.absoluteString), @"each private file delivered to print recorder", failures);
                workspaceCheck(!contains(rs, @"open", nil), @"AndPrint must not open documents instead", failures);
            }
            if ([c isEqual:@"without-activation"])
                workspaceCheck([[NSWorkspace sharedWorkspace] frontmostApplication].processIdentifier != call.returned.processIdentifier,
                    @"fixture is not frontmost at observation deadline", failures);
            if ([c isEqual:@"hide"]) {
                NSTimeInterval hiddenDeadline = [[NSProcessInfo processInfo] systemUptime] + 1;
                while (!call.returned.hidden && [[NSProcessInfo processInfo] systemUptime] < hiddenDeadline && !workspaceInterrupted)
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
                workspaceCheck(call.returned.hidden, @"fixture hidden after finished-launching and bounded state observation", failures);
            }
        }
    } @catch (NSException *exception) {
        [result setObject:@{ @"name": exception.name, @"reason": exception.reason ?: @"" } forKey:@"harness_exception"];
        [failures addObject:@"harness/evidence exception, not an observed native result"];
    } @finally {
        /* Bounded collection includes launches caused by failing/empty calls.
         * Termination is authorized only by the exact controlled bundle URL. */
        NSMutableArray *apps = [NSMutableArray array];
        NSTimeInterval end = [[NSProcessInfo processInfo] systemUptime] + 3;
        do {
            for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications])
                if (owned(a, app) && ![apps containsObject:a]) [apps addObject:a];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        } while ([[NSProcessInfo processInfo] systemUptime] < end && !workspaceInterrupted);
        @try {
            NSMutableArray *sideEffects = [NSMutableArray array];
            for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:events error:NULL]) {
                if (![name hasSuffix:@".jsonl"]) continue;
                pid_t pid = [[name stringByDeletingPathExtension] intValue];
                if (pid <= 0 || ![[NSString stringWithFormat:@"%d.jsonl", pid] isEqual:name])
                    [NSException raise:@"WorkspaceOptionsEvidenceError" format:@"unexpected evidence filename"];
                NSDictionary *snapshot = recordSnapshot(events, pid);
                [sideEffects addObject:@{ @"pid": @(pid), @"snapshot": snapshot }];
                workspaceCheck([[snapshot objectForKey:@"incomplete_tail_bytes"] unsignedIntegerValue] == 0,
                    @"complete side-effect JSONL at observation deadline", failures);
            }
            [result setObject:sideEffects forKey:@"side_effects"];
            if ([c isEqual:@"default"] || [c isEqual:@"files"] || [c isEqual:@"without-recents"]) {
                NSArray *recentFiles = [c isEqual:@"default"] ? @[] : @[
                    [NSURL fileURLWithPath:[report stringByAppendingPathComponent:@"one.txt"]],
                    [NSURL fileURLWithPath:[report stringByAppendingPathComponent:@"two.txt"]]];
                [result setObject:optionsRecents(app, recentFiles) forKey:@"recents_after"];
                [result setObject:@"read-only bounded matching counts; suppression requires an observable positive control; forwarding alone is not proof" forKey:@"recents_limit"];
            }
        } @catch (NSException *exception) {
            [failures addObject:@"side-effect/recents evidence could not be measured"];
        }
        BOOL cleaned = YES;
        for (NSRunningApplication *a in apps) if (owned(a, app)) {
            [a terminate];
            end = [[NSProcessInfo processInfo] systemUptime] + 3;
            while (!a.terminated && [[NSProcessInfo processInfo] systemUptime] < end)
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            if (!a.terminated && owned(a, app)) [a forceTerminate];
            end = [[NSProcessInfo processInfo] systemUptime] + 3;
            while (!a.terminated && [[NSProcessInfo processInfo] systemUptime] < end)
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            cleaned &= a.terminated;
        }
        [result setObject:@(cleaned) forKey:@"cleanup_completed"];
        workspaceCheck(cleaned, @"private fixture cleanup completed", failures);
        [call.returned release]; [call.error release]; [call.exception release];
    }
finish:
    if (workspaceInterrupted) [failures addObject:@"interrupted; observation incomplete"];
    [result setObject:failures forKey:@"failures"];
    rc = failures.count ? 1 : rc;
    [result setObject:rc ? @"failed" : (observation ? @"observed-only" : @"passed") forKey:@"disposition"];
    [result setObject:@"bounded event/final-state observations only; recents, grouping and async timing need explicit contract review" forKey:@"observation_limit"];
writeReport:;
    BOOL written = optionsWrite(output, [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL]);
    if (close(output)) written = NO;
    if (!written) rc = 1;
    printf("%s: %s\n", c.UTF8String, [[result objectForKey:@"disposition"] UTF8String]);
    [pool drain];
    return rc;
}
#endif
