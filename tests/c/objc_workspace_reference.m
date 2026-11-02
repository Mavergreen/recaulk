/* Native contract oracle only. Never activates Recaulk or replaces a method.
 * Contracts: pinned NSWorkspace.h configuration comments and Apple's DocC
 * open(_:withApplicationAt:options:configuration:) entry. Undocumented cases
 * deliberately report observed-only, even when the native call succeeds. */
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#include <unistd.h>
#include <math.h>
#include <signal.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <limits.h>
static volatile sig_atomic_t workspaceInterrupted;
static void workspaceSignal(int number) { workspaceInterrupted = number; }
static void installWorkspaceSignals(void) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = workspaceSignal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGHUP, &action, NULL);
}

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
static BOOL stringArray(id value) {
    if (![value isKindOfClass:[NSArray class]]) return NO;
    for (id s in value) if (![s isKindOfClass:[NSString class]]) return NO;
    return YES;
}
static BOOL validRecord(id r, pid_t pid, NSUInteger sequence) {
    if (![r isKindOfClass:[NSDictionary class]]) return NO;
    id kind = [r objectForKey:@"kind"], p = [r objectForKey:@"pid"], n = [r objectForKey:@"sequence"];
    if (![kind isKindOfClass:[NSString class]] || ![p isKindOfClass:[NSNumber class]] || ![n isKindOfClass:[NSNumber class]] ||
        [p doubleValue] != pid || [n doubleValue] != sequence) return NO;
    if ([kind isEqual:@"startup"]) {
        id arch = [r objectForKey:@"architecture"], sentinel = [r objectForKey:@"sentinel"];
        return sequence == 0 && stringArray([r objectForKey:@"argv"]) && [[r objectForKey:@"argv"] count] > 0 &&
            ([sentinel isKindOfClass:[NSString class]] || sentinel == [NSNull null]) &&
            [@[@"arm64", @"x86_64", @"i386"] containsObject:arch ?: @""];
    }
    if ([kind isEqual:@"finished-launching"]) return sequence > 0;
    return sequence > 0 && [@[@"open", @"open-application", @"reopen", @"print", @"custom"] containsObject:kind] &&
        stringArray([r objectForKey:@"urls"]) && [[r objectForKey:@"direct_string"] isKindOfClass:[NSString class]] &&
        [[r objectForKey:@"event_class"] isKindOfClass:[NSNumber class]] && [[r objectForKey:@"event_id"] isKindOfClass:[NSNumber class]];
}
static NSDictionary *recordSnapshot(NSString *dir, pid_t pid) {
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.jsonl", pid]];
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    NSData *data = nil;
    if (fd < 0 && errno != ENOENT) [NSException raise:@"WorkspaceEvidenceError" format:@"cannot safely open fixture records for PID %d", pid];
    if (fd >= 0) {
        struct stat st;
        if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != geteuid() || st.st_nlink != 1 || (st.st_mode & 022)) {
            close(fd);
            [NSException raise:@"WorkspaceEvidenceError" format:@"unsafe fixture record file for PID %d", pid];
        }
        NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        @try { data = [handle readDataToEndOfFile]; }
        @finally { [handle release]; }
    }
    NSMutableArray *out = [NSMutableArray array];
    const unsigned char *bytes = data.bytes;
    NSUInteger start = 0;
    for (NSUInteger i = 0; i < data.length; i++) {
        if (bytes[i] != '\n') continue;
        NSData *line = [data subdataWithRange:NSMakeRange(start, i-start)];
        id r = [NSJSONSerialization JSONObjectWithData:line options:0 error:NULL];
        if (!validRecord(r, pid, out.count)) [NSException raise:@"WorkspaceEvidenceError" format:@"invalid completed fixture record in PID %d", pid];
        [out addObject:r]; start = i + 1;
    }
    /* Only newline-terminated records are complete, including when a partial
     * UTF-8 codepoint is present. Polling retries a tail; it is never a pass. */
    return @{@"records": out, @"incomplete_tail_bytes": @(data.length-start), @"file_missing": @(!data)};
}
static NSArray *records(NSString *dir, pid_t pid) {
    return [recordSnapshot(dir, pid) objectForKey:@"records"];
}
static BOOL contains(NSArray *rs, NSString *kind, NSString *url) {
    for (NSDictionary *r in rs) {
        if (![[r objectForKey:@"kind"] isEqual:kind]) continue;
        if (!url) return YES;
        for (NSString *actual in [r objectForKey:@"urls"]) {
            if ([actual isEqual:url]) return YES;
            NSURL *expectedURL = [NSURL URLWithString:url];
            NSURL *actualURL = [NSURL URLWithString:actual];
            /* Launch Services resolves file aliases such as /var -> /private/var.
             * Compare only file referents this way; non-file URLs stay exact. */
            if ([expectedURL isFileURL] && [actualURL isFileURL] &&
                [[expectedURL URLByResolvingSymlinksInPath] isEqual:[actualURL URLByResolvingSymlinksInPath]]) return YES;
        }
    }
    return NO;
}
static BOOL startupMatches(NSDictionary *r, NSArray *arguments, NSString *environment) {
    NSArray *argv = [r objectForKey:@"argv"];
    return [argv isKindOfClass:[NSArray class]] && [argv count] == [arguments count] + 1 &&
        [[argv subarrayWithRange:NSMakeRange(1, [arguments count])] isEqual:arguments] &&
        [[r objectForKey:@"sentinel"] isEqual:environment];
}
static BOOL customPayload(NSArray *rs, NSString *payload) {
    for (NSDictionary *r in rs) if ([[r objectForKey:@"kind"] isEqual:@"custom"] && [[r objectForKey:@"direct_string"] isEqual:payload]) return YES;
    return NO;
}
static NSDictionary *waitRecordSnapshot(NSString *dir, pid_t pid, NSArray *urls, NSString *kind, NSTimeInterval timeout) {
    if (!isfinite(timeout) || timeout < 0) [NSException raise:@"WorkspaceEvidenceError" format:@"invalid observation deadline"];
    NSTimeInterval deadline = [[NSProcessInfo processInfo] systemUptime] + timeout;
    for (;;) {
        NSDictionary *snapshot = recordSnapshot(dir, pid);
        NSArray *rs = [snapshot objectForKey:@"records"];
        BOOL ready = contains(rs, @"startup", nil) && [[snapshot objectForKey:@"incomplete_tail_bytes"] unsignedIntegerValue] == 0;
        if (kind) ready &= contains(rs, kind, nil);
        for (NSURL *u in urls) ready &= contains(rs, @"open", [u absoluteString]);
        BOOL expired = [[NSProcessInfo processInfo] systemUptime] >= deadline;
        if (ready || expired || workspaceInterrupted) {
            NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:snapshot];
            [result setObject:@(ready) forKey:@"requirements_observed"];
            [result setObject:@(!ready && expired) forKey:@"deadline_expired"];
            [result setObject:@(timeout) forKey:@"deadline_seconds"];
            [result setObject:@(workspaceInterrupted != 0) forKey:@"interrupted"];
            return result;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}
static NSArray *waitRecords(NSString *dir, pid_t pid, NSArray *urls, NSString *kind) {
    return [waitRecordSnapshot(dir, pid, urls, kind, 12) objectForKey:@"records"];
}
static BOOL owned(NSRunningApplication *app, NSURL *url) {
    return app && [[[app bundleURL] URLByResolvingSymlinksInPath] isEqual:[url URLByResolvingSymlinksInPath]];
}
static void workspaceCheck(BOOL ok, NSString *message, NSMutableArray *failures) {
    if (!ok) [failures addObject:message];
}
static NSString *canonicalFixturePath(NSString *path) {
    char resolved[PATH_MAX];
    return realpath(path.fileSystemRepresentation, resolved) ? [NSString stringWithUTF8String:resolved] : nil;
}
static BOOL safeFixturePath(NSString *path) {
    if (![path isAbsolutePath]) return NO;
    NSString *cursor = @"/";
    for (NSString *part in [path pathComponents]) {
        if ([part isEqual:@"/"]) continue;
        if ([part isEqual:@"."] || [part isEqual:@".."]) return NO;
        cursor = [cursor stringByAppendingPathComponent:part];
        struct stat st;
        if (lstat(cursor.fileSystemRepresentation, &st)) return NO;
        if (S_ISLNK(st.st_mode)) {
            /* Preserve native /var and /tmp lexical-path coverage, but no
             * caller-created aliases inside the private fixture tree. */
            NSString *resolved = canonicalFixturePath(cursor);
            BOOL systemAlias = st.st_uid == 0 &&
                (([cursor isEqual:@"/var"] && [resolved isEqual:@"/private/var"]) ||
                 ([cursor isEqual:@"/tmp"] && [resolved isEqual:@"/private/tmp"]));
            if (!systemAlias) return NO;
        }
    }
    return YES;
}
static BOOL fixturePrerequisites(NSURL *app, NSString *report, NSString *events) {
    if (![app isFileURL] || (app.host.length && ![app.host isEqual:@"localhost"]) || app.query || app.fragment ||
        !safeFixturePath(app.path) || !safeFixturePath(events)) return NO;
    NSString *expected = canonicalFixturePath([report stringByAppendingPathComponent:@"Probe.app"]);
    if (![canonicalFixturePath(app.path) isEqual:expected]) return NO;
    NSString *executable = [app.path stringByAppendingPathComponent:@"Contents/MacOS/WorkspaceProbe"];
    NSString *info = [app.path stringByAppendingPathComponent:@"Contents/Info.plist"];
    if (!safeFixturePath(executable) || !safeFixturePath(info) || ![[NSFileManager defaultManager] isExecutableFileAtPath:executable]) return NO;
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:info];
    id identifier = [plist objectForKey:@"CFBundleIdentifier"];
    id configuredReport = [plist objectForKey:@"WorkspaceProbeReportDirectory"];
    struct stat st;
    if (stat(events.fileSystemRepresentation, &st) || !S_ISDIR(st.st_mode) || st.st_uid != geteuid() || (st.st_mode & 022)) return NO;
    return [identifier isKindOfClass:[NSString class]] && [identifier hasPrefix:@"org.mavergreen."] &&
        [[plist objectForKey:@"CFBundleExecutable"] isEqual:@"WorkspaceProbe"] &&
        [[plist objectForKey:@"CFBundlePackageType"] isEqual:@"APPL"] &&
        [configuredReport isKindOfClass:[NSString class]] && [configuredReport isAbsolutePath] &&
        [canonicalFixturePath(configuredReport) isEqual:canonicalFixturePath(events)];
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if (argc != 4) { fprintf(stderr, "usage: reference CASE APP_URL REPORT_DIR\n"); return 1; }
    installWorkspaceSignals();
    NSString *c = [NSString stringWithUTF8String:argv[1]];
    NSURL *appURL = [NSURL URLWithString:[NSString stringWithUTF8String:argv[2]]];
    NSString *appInput = [NSString stringWithUTF8String:argv[2]];
    if ([appInput isAbsolutePath]) appURL = [NSURL fileURLWithPath:appInput];
    else if (![appURL isFileURL]) appURL = nil;
    NSString *report = [NSString stringWithUTF8String:argv[3]];
    if (![report isAbsolutePath]) report = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:report];
    if (!safeFixturePath(report)) { fprintf(stderr, "unsafe report directory\n"); return 1; }
    int reportFD = open(report.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    struct stat reportStat;
    if (reportFD < 0 || fstat(reportFD, &reportStat) || !S_ISDIR(reportStat.st_mode) || reportStat.st_uid != geteuid() || (reportStat.st_mode & 077) || fchdir(reportFD)) {
        if (reportFD >= 0) close(reportFD);
        fprintf(stderr, "report directory must be private and owned by caller\n"); return 1;
    }
    /* Reserve the output without following/replacing anything. fchdir pins output
     * to the opened directory on 10.9, whose SDK lacks the newer *at APIs. */
    int outputFD = open("controller.json", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    close(reportFD);
    if (outputFD < 0) { fprintf(stderr, "controller output already exists or is unsafe\n"); return 1; }
    NSString *events = [report stringByAppendingPathComponent:@"events"];
    SEL sel = @selector(openURLs:withApplicationAtURL:options:configuration:error:);
    Method method = class_getInstanceMethod([NSWorkspace class], sel);
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:c, @"case", [[NSProcessInfo processInfo] operatingSystemVersionString], @"os", hostArch(), @"architecture", nil];
    NSString *caseNonce = [[NSProcessInfo processInfo] globallyUniqueString];
    NSString *customSentinel = [@"custom sentinel " stringByAppendingString:caseNonce];
    [result setObject:caseNonce forKey:@"case_nonce"];
    NSMutableArray *failures = [NSMutableArray array];
    NSMutableArray *calls = [NSMutableArray array];
    NSMutableArray *cleanup = [NSMutableArray array];
    [result setObject:calls forKey:@"calls"];
    int rc = 0;
    NSArray *known = [@"stopped reused multiple mixed new-instance startup reuse-configuration without-activation custom-event custom-reuse invalid-app nil-error nil-error-failure ownership empty empty-custom conflicting-event unknown-key impossible-architecture asynchronous architecture" componentsSeparatedByString:@" "];
    if (![known containsObject:c]) {
        [failures addObject:@"unknown case"]; rc = 1; goto finish;
    }
    if (!fixturePrerequisites(appURL, report, events)) {
        [failures addObject:@"missing fixture/report prerequisites"]; rc = 1; goto finish;
    }
    if ([c isEqual:@"mixed"]) {
        struct stat st;
        if (!lstat("sentinel.txt", &st) || errno != ENOENT) {
            [failures addObject:@"mixed fixture output already exists or cannot be inspected"]; rc = 1; goto finish;
        }
    }
    if (!method) { [result setObject:@"system-method-absent" forKey:@"disposition"]; rc = 77; goto write; }
    [result setObject:[NSString stringWithUTF8String:method_getTypeEncoding(method)] forKey:@"method_encoding"];
    if (workspaceInterrupted) goto finish;
    @try {
        BOOL reuse = [@[@"reused", @"new-instance", @"reuse-configuration", @"custom-reuse"] containsObject:c];
        BOOL observation = [@[@"empty", @"empty-custom", @"conflicting-event", @"unknown-key", @"impossible-architecture", @"asynchronous"] containsObject:c];
        [result setObject:[NSNumber numberWithBool:observation] forKey:@"observation_only"];
        NSURL *one = [NSURL URLWithString:[@"https://workspace-probe.invalid/sentinel-one/" stringByAppendingString:caseNonce]];
        NSURL *two = [NSURL URLWithString:[@"https://workspace-probe.invalid/sentinel-two/" stringByAppendingString:caseNonce]];
        NSMutableArray *urls = [NSMutableArray arrayWithObject:one];
        if ([c isEqual:@"multiple"]) [urls addObject:two];
        if ([c isEqual:@"mixed"]) {
            NSString *file = [report stringByAppendingPathComponent:@"sentinel.txt"];
            int fd = open("sentinel.txt", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
            BOOL written = fd >= 0;
            if (written) {
                ssize_t count;
                do { count = write(fd, "fixture", 7); } while (count < 0 && errno == EINTR);
                written = count == 7;
                if (close(fd)) written = NO;
            }
            if (!written) [NSException raise:@"WorkspaceEvidenceError" format:@"cannot exclusively create mixed fixture file"];
            [urls addObject:[NSURL fileURLWithPath:file]];
        }
        if ([c isEqual:@"empty"] || [c isEqual:@"empty-custom"]) [urls removeAllObjects];
        [result setObject:@{@"source": @"Pinned SDK NSWorkspace.h configuration comments; NSNumber architecture values from NSBundle.h", @"arguments_type": @"NSArray<NSString *>", @"environment_type": @"NSDictionary<NSString *, NSString *>", @"apple_event_type": @"NSAppleEventDescriptor", @"architecture_type": @"NSNumber containing NSBundleExecutableArchitecture", @"ownership_limit": @"Tests explicit caller retains across an autorelease pool, not internal autorelease/retain counts", @"activation_limit": @"Final frontmost state only; transient activation is unmeasured"} forKey:@"contract_provenance"];
        NSMutableDictionary *config = [NSMutableDictionary dictionaryWithObjectsAndKeys:@[@"--workspace-sentinel", @"argv exact value"], NSWorkspaceLaunchConfigurationArguments, @{@"WORKSPACE_PROBE_SENTINEL": @"environment exact value"}, NSWorkspaceLaunchConfigurationEnvironment, nil];
        NSRunningApplication *first = nil;
        if (reuse) {
            NSError *e = nil;
            first = [[NSWorkspace sharedWorkspace] openURLs:@[two] withApplicationAtURL:appURL options:NSWorkspaceLaunchWithoutActivation configuration:config error:&e];
            if (owned(first, appURL)) [cleanup addObject:first];
            NSArray *rs = waitRecords(events, [first processIdentifier], @[two], nil);
            workspaceCheck(owned(first, appURL) && contains(rs, @"open", [two absoluteString]), @"seed instance received URL", failures);
            [result setObject:rs forKey:@"seed_evidence"];
            [result setObject:[NSDictionary dictionaryWithDictionary:config] forKey:@"seed_configuration"];
            [result setObject:@([first processIdentifier]) forKey:@"seed_pid"];
            [config setObject:@[@"--must-not-reach-existing-process"] forKey:NSWorkspaceLaunchConfigurationArguments];
            [config setObject:@{@"WORKSPACE_PROBE_SENTINEL": @"must not replace startup environment"} forKey:NSWorkspaceLaunchConfigurationEnvironment];
        }
        if ([c isEqual:@"custom-event"] || [c isEqual:@"custom-reuse"] || [c isEqual:@"empty-custom"] || [c isEqual:@"conflicting-event"]) {
            NSAppleEventDescriptor *ev = [NSAppleEventDescriptor appleEventWithEventClass:'WPrb' eventID:'ping' targetDescriptor:[NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID data:[[[NSBundle bundleWithURL:appURL] bundleIdentifier] dataUsingEncoding:NSUTF8StringEncoding]] returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
            [ev setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:customSentinel] forKeyword:keyDirectObject];
            [config setObject:ev forKey:NSWorkspaceLaunchConfigurationAppleEvent];
        }
        if ([c isEqual:@"unknown-key"]) [config setObject:@"sentinel" forKey:@"org.mavergreen.unknown-configuration-key"];
        if ([c isEqual:@"architecture"] || [c isEqual:@"impossible-architecture"]) {
#if defined(__arm64__)
            NSNumber *arch = @(NSBundleExecutableArchitectureARM64);
#else
            NSNumber *arch = @(NSBundleExecutableArchitectureX86_64);
#endif
            if ([c isEqual:@"impossible-architecture"]) arch = @(0x7fffffff);
            [config setObject:arch forKey:NSWorkspaceLaunchConfigurationArchitecture];
        }
        NSWorkspaceLaunchOptions flags = NSWorkspaceLaunchWithoutActivation;
        if ([c isEqual:@"new-instance"]) flags |= NSWorkspaceLaunchNewInstance;
        if ([c isEqual:@"asynchronous"]) flags |= NSWorkspaceLaunchAsync;
        NSURL *target = ([c isEqual:@"invalid-app"] || [c isEqual:@"nil-error-failure"]) ? [NSURL fileURLWithPath:[report stringByAppendingPathComponent:@"DoesNotExist.app"]] : appURL;
        NSRunningApplication *front = [NSWorkspace sharedWorkspace].frontmostApplication;
        pid_t frontPID = [front processIdentifier];
        NSAutoreleasePool *inner = [NSAutoreleasePool new];
        NSError *error = nil;
        NSRunningApplication *returned = nil;
        if (workspaceInterrupted) [NSException raise:@"WorkspaceInterrupted" format:@"interrupted before native invocation"];
        /* Only exceptions from this invocation are native behavior. Evidence,
         * JSON and harness failures remain failures even in observation cases. */
        @try {
            returned = [[[NSWorkspace sharedWorkspace] openURLs:urls withApplicationAtURL:target options:flags configuration:config error:[c hasPrefix:@"nil-error"] ? NULL : &error] retain];
        } @catch (NSException *native) {
            [result setObject:@{@"name": native.name, @"reason": native.reason ?: @""} forKey:@"native_exception"];
            if (!observation) [failures addObject:@"native API raised exception"];
        }
        [error retain];
        NSDictionary *immediate = @{ @"finished_launching": @([returned isFinishedLaunching]), @"terminated": @([returned isTerminated]) };
        [immediate retain];
        [inner drain]; /* normal +0 return/out-error: explicit retains must survive this boundary */
        if (owned(returned, appURL) && ![cleanup containsObject:returned]) [cleanup addObject:returned];
        pid_t pid = [returned processIdentifier];
        NSMutableDictionary *call = [NSMutableDictionary dictionaryWithObjectsAndKeys:@(pid), @"returned_pid", [returned.bundleURL absoluteString] ?: (id)[NSNull null], @"returned_bundle_url", error.domain ?: (id)[NSNull null], @"error_domain", error ? @(error.code) : (id)[NSNull null], @"error_code", immediate, @"immediate_state", @(flags), @"options", nil];
        NSMutableDictionary *configurationEvidence = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [config objectForKey:NSWorkspaceLaunchConfigurationArguments], NSWorkspaceLaunchConfigurationArguments,
            [config objectForKey:NSWorkspaceLaunchConfigurationEnvironment], NSWorkspaceLaunchConfigurationEnvironment, nil];
        id architecture = [config objectForKey:NSWorkspaceLaunchConfigurationArchitecture];
        if (architecture) [configurationEvidence setObject:architecture forKey:NSWorkspaceLaunchConfigurationArchitecture];
        NSAppleEventDescriptor *configuredEvent = [config objectForKey:NSWorkspaceLaunchConfigurationAppleEvent];
        if (configuredEvent) [configurationEvidence setObject:@{@"event_class": @(configuredEvent.eventClass), @"event_id": @(configuredEvent.eventID), @"direct_string": [[configuredEvent paramDescriptorForKeyword:keyDirectObject] stringValue] ?: @"", @"target_bundle_id": [[NSBundle bundleWithURL:appURL] bundleIdentifier]} forKey:NSWorkspaceLaunchConfigurationAppleEvent];
        id unknown = [config objectForKey:@"org.mavergreen.unknown-configuration-key"];
        if (unknown) [configurationEvidence setObject:unknown forKey:@"org.mavergreen.unknown-configuration-key"];
        [call setObject:configurationEvidence forKey:@"configuration"];
        [call setObject:target.absoluteString forKey:@"requested_application_url"];
        NSMutableArray *requestedURLs = [NSMutableArray array];
        for (NSURL *u in urls) [requestedURLs addObject:u.absoluteString];
        [call setObject:requestedURLs forKey:@"requested_urls"];
        [calls addObject:call];
        NSArray *expected = observation ? @[] : urls;
        NSDictionary *snapshot = returned ? waitRecordSnapshot(events, pid, expected, ([c isEqual:@"custom-event"] || [c isEqual:@"custom-reuse"]) ? @"custom" : nil, 12) : nil;
        NSArray *rs = snapshot ? [snapshot objectForKey:@"records"] : @[];
        [call setObject:rs forKey:@"evidence"];
        if (snapshot) {
            NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:snapshot];
            [status removeObjectForKey:@"records"];
            [call setObject:status forKey:@"evidence_observation"];
            workspaceCheck(![[snapshot objectForKey:@"deadline_expired"] boolValue], @"returned PID evidence incomplete at deadline (cannot-measure)", failures);
        }
        if ([c isEqual:@"invalid-app"]) workspaceCheck(!returned && error && [error.domain length], @"invalid app returns nil and usable NSError across pool boundary", failures);
        else if ([c isEqual:@"nil-error-failure"]) workspaceCheck(!returned && !error, @"invalid app with NULL error output returns nil without exception", failures);
        else if (!observation) {
            workspaceCheck(owned(returned, appURL), @"returned application is fixture bundle", failures);
            workspaceCheck(pid > 0 && contains(rs, @"startup", nil), @"returned PID has startup evidence", failures);
            for (NSURL *u in urls) workspaceCheck(contains(rs, @"open", u.absoluteString), @"returned PID received exact URL", failures);
            if (reuse) workspaceCheck([c isEqual:@"new-instance"] ? pid != first.processIdentifier : pid == first.processIdentifier, @"reuse/new-instance PID relationship", failures);
            for (NSDictionary *r in rs) if ([[r objectForKey:@"kind"] isEqual:@"startup"]) {
                BOOL newInstance = [c isEqual:@"new-instance"];
                workspaceCheck(startupMatches(r, newInstance ? @[@"--must-not-reach-existing-process"] : @[@"--workspace-sentinel", @"argv exact value"], newInstance ? @"must not replace startup environment" : @"environment exact value"), @"exact startup argv sequence (excluding argv[0]) and environment; no injected extras", failures);
                if ([c isEqual:@"architecture"]) workspaceCheck([[r objectForKey:@"architecture"] isEqual:hostArch()], @"requested host architecture actually executed", failures);
            }
            if ([c isEqual:@"custom-event"] || [c isEqual:@"custom-reuse"]) workspaceCheck(customPayload(rs, customSentinel), @"exact custom initial Apple event payload delivered", failures);
            if ([c isEqual:@"without-activation"]) workspaceCheck([[NSWorkspace sharedWorkspace].frontmostApplication processIdentifier] != pid && frontPID != pid, @"without-activation does not activate fixture", failures);
        }
        [immediate release]; [returned release]; [error release];
        /* Capture every fixture-owned PID, including side effects of failing calls.
         * Bundle identity, not process name or untrusted log PID, authorizes termination. */
        NSDate *observationDeadline = [NSDate dateWithTimeIntervalSinceNow:3];
        do {
            for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications]) if (owned(a, appURL) && ![cleanup containsObject:a]) [cleanup addObject:a];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        } while (observationDeadline.timeIntervalSinceNow > 0 && !workspaceInterrupted);
        NSMutableArray *sideEffects = [NSMutableArray array];
        /* Include logs of exited fixture processes, never use their untrusted PID
         * to authorize termination. Only the running-app identity above does so. */
        for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:events error:NULL]) {
            if (![file hasSuffix:@".jsonl"]) continue;
            pid_t recordedPID = [[file stringByDeletingPathExtension] intValue];
            NSDictionary *snapshot = recordSnapshot(events, recordedPID);
            [sideEffects addObject:@{@"pid": @(recordedPID), @"records": [snapshot objectForKey:@"records"], @"incomplete_tail_bytes": [snapshot objectForKey:@"incomplete_tail_bytes"]}];
            if ([[snapshot objectForKey:@"incomplete_tail_bytes"] unsignedIntegerValue]) {
                [result setObject:@"incomplete JSONL tail remains at observation deadline" forKey:@"missing_observation"];
                [failures addObject:@"incomplete fixture record at deadline; cannot measure complete evidence"];
            }
        }
        [result setObject:sideEffects forKey:@"side_effects"];
        [result setObject:@3 forKey:@"side_effect_observation_seconds"];
        [result setObject:@"bounded snapshot only; events after deadline and processes exiting without logs are unmeasured" forKey:@"observation_limit"];
        if (returned && !contains(rs, @"startup", nil)) [result setObject:@"returned PID startup not observed before deadline" forKey:@"missing_observation"];
        if ([c isEqual:@"architecture"]) [result setObject:@"dual-slice capability not measured" forKey:@"missing_observation"];
    } @catch (NSException *e) {
        [result setObject:@{@"name": e.name, @"reason": e.reason ?: @""} forKey:@"harness_exception"];
        [failures addObject:@"harness/evidence exception (not native behavior)"];
        [result setObject:@"side-effect collection incomplete after harness failure; raw files retained" forKey:@"missing_observation"];
        for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications]) if (owned(a, appURL) && ![cleanup containsObject:a]) [cleanup addObject:a];
    }
finish:;
    BOOL cleanupCompleted = YES;
    for (NSRunningApplication *a in cleanup) if (owned(a, appURL)) {
        [a terminate];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!a.terminated && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!a.terminated && owned(a, appURL)) [a forceTerminate];
        deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!a.terminated && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        cleanupCompleted &= a.terminated;
    }
    if (workspaceInterrupted) {
        [result setObject:@(workspaceInterrupted) forKey:@"interrupted_signal"];
        [result setObject:@"interrupted bounded observation; evidence is incomplete" forKey:@"missing_observation"];
        [failures addObject:@"controller interrupted"];
    }
    [result setObject:@(cleanupCompleted) forKey:@"cleanup_completed"];
    if (!cleanupCompleted) [failures addObject:@"fixture cleanup did not complete before deadline"];
    [result setObject:failures forKey:@"failures"];
    rc = [failures count] ? 1 : rc;
    [result setObject:rc ? @"failed" : ([[result objectForKey:@"observation_only"] boolValue] ? @"observed-only" : @"passed") forKey:@"disposition"];
write:
    {
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        if (!data) rc = 1;
        const unsigned char *bytes = data.bytes;
        NSUInteger remaining = data.length;
        while (remaining) {
            ssize_t count = write(outputFD, bytes, remaining);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) { rc = 1; break; }
            bytes += count; remaining -= count;
        }
        if (close(outputFD)) rc = 1;
        printf("%s: %s\n", c.UTF8String, [[result objectForKey:@"disposition"] UTF8String]);
    }
    [pool drain];
    return rc;
}
