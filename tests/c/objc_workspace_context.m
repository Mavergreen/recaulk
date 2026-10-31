/* Stable app-hosted runner. No permission request except explicit authorize.
 * Unit controls below are archive/lock tests, never native contract evidence. */
#define main workspaceReferenceMain
#include "objc_workspace_reference.m"
#undef main
#ifndef CONTEXT_SOURCE_ID
#error context source fingerprint is required
#endif
static NSString *contextRoot;
static NSURL *contextProbe;
static BOOL contextOwnsFixture;
static void demand(BOOL condition, NSString *reason) {
    if (!condition) [NSException raise:@"WorkspaceContextError" format:@"%@",reason];
}
static NSString *at(NSString *root, NSString *name) { return [root stringByAppendingPathComponent:name]; }
static BOOL exists(NSString *p) { struct stat s; return lstat(p.fileSystemRepresentation,&s)==0; }
static void privateDirectory(NSString *p) { demand(mkdir(p.fileSystemRepresentation,0700)==0, [@"directory exists or cannot be created: " stringByAppendingString:p]); }
static void save(NSString *p, NSDictionary *value) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:NULL];
    demand(d != nil,@"cannot encode report");
    int fd = open(p.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    demand(fd>=0,[@"output exists or unsafe: " stringByAppendingString:p]);
    const unsigned char *b = d.bytes; NSUInteger left=d.length; BOOL ok=YES;
    while(left) { ssize_t n=write(fd,b,left); if(n<0 && errno==EINTR) continue; if(n<=0){ok=NO;break;} b+=n;left-=n; }
    if(close(fd))ok=NO; demand(ok,@"cannot write report");
}
static NSDictionary *load(NSString *p) {
    struct stat s;
    demand(lstat(p.fileSystemRepresentation,&s)==0 && S_ISREG(s.st_mode) && s.st_nlink==1 && s.st_uid==geteuid(),@"missing or unsafe control report");
    NSData *d=[NSData dataWithContentsOfFile:p];
    id j=d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    demand([j isKindOfClass:[NSDictionary class]],@"missing/malformed/partial control JSON"); return j;
}
static NSString *text(NSString *p) { return [[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; }
static NSArray *live(NSURL *url) {
    NSMutableArray *a=[NSMutableArray array];
    for(NSRunningApplication *app in [NSWorkspace sharedWorkspace].runningApplications) if(owned(app,url)) [a addObject:app];
    return a;
}
static BOOL clean(NSURL *url) {
    BOOL ok=YES;
    for(NSRunningApplication *app in live(url)) {
        [app terminate]; NSTimeInterval end=[NSProcessInfo processInfo].systemUptime+3;
        while(!app.terminated && [NSProcessInfo processInfo].systemUptime<end) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        if(!app.terminated && owned(app,url)) [app forceTerminate];
        end=[NSProcessInfo processInfo].systemUptime+3;
        while(!app.terminated && [NSProcessInfo processInfo].systemUptime<end) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        ok &= app.terminated;
    }
    return ok;
}
static void moveFresh(NSString *from, NSString *to) {
    demand(!exists(to),@"refusing archive replacement");
    demand([[NSFileManager defaultManager] moveItemAtPath:from toPath:to error:NULL],@"cannot archive state (same private filesystem recommended)");
}
static void archiveCase(NSString *root, NSString *report, NSString *name, int rc) {
    NSDictionary *j=load(at(root,@"controller.json"));
    demand([[j objectForKey:@"case"] isEqual:name],@"case identity mismatch");
    NSString *disposition=[j objectForKey:@"disposition"];
    demand([@[@"passed",@"failed",@"observed-only",@"system-method-absent"] containsObject:disposition],@"invalid case disposition");
    demand(rc==77 || [[j objectForKey:@"cleanup_completed"] boolValue],@"case cleanup incomplete");
    demand(live([NSURL fileURLWithPath:at(root,@"Probe.app")]).count==0,@"fixture still running at archive boundary");
    NSString *dest=at(report,name); privateDirectory(dest);
    save(at(dest,@"archive.json"),@{@"case":name,@"controller_exit":@(rc),@"original_context":root,@"original_events":at(root,@"events"),@"bounded_observation_only":@YES});
    moveFresh(at(root,@"controller.json"),at(dest,@"controller.json"));
    moveFresh(at(root,@"events"),at(dest,@"events"));
    privateDirectory(at(root,@"events"));
    if(exists(at(root,@"sentinel.txt"))) {
        demand([name isEqual:@"mixed"],@"unexpected sentinel output");
        struct stat s; demand(lstat([at(root,@"sentinel.txt") fileSystemRepresentation],&s)==0 && S_ISREG(s.st_mode) && s.st_nlink==1 && s.st_uid==geteuid(),@"unsafe mixed sentinel");
        moveFresh(at(root,@"sentinel.txt"),at(dest,@"sentinel.txt"));
    }
}
static BOOL acquire(NSString *root) { return mkdir([at(root,@".run-lock") fileSystemRepresentation],0700)==0; }
static void awaitActor(NSRunningApplication *actor, NSURL *sender, NSTimeInterval timeout) {
    demand(owned(actor,sender),@"sender actor identity mismatch");
    NSTimeInterval end=[NSProcessInfo processInfo].systemUptime+timeout, interruptedAt=0;
    for(;;) {
        if(workspaceInterrupted && !interruptedAt) {
            interruptedAt=[NSProcessInfo processInfo].systemUptime;
            if(owned(actor,sender) && !actor.terminated) kill(actor.processIdentifier,workspaceInterrupted);
        }
        if(actor.terminated)return;
        demand([NSProcessInfo processInfo].systemUptime<end && (!interruptedAt || [NSProcessInfo processInfo].systemUptime-interruptedAt<20),@"sender deadline/interrupt cleanup exceeded");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}
static void validateUnsignedState(NSString *root) {
    NSArray *allowed=@[@"Sender.app",@"Probe.app",@"events",@"context.path",@"source.sha256",@"source.commit",@"architecture",@"sdk.path",@"sdk.sha256",@"sdk-fetch.sha256",@"compiler.txt",@"apps.sha256",@"sender-signature.txt",@"probe-signature.txt",@"preparation.json",@".run-lock",@"request.json",@"response.json"];
    for(NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL]) demand([allowed containsObject:name],[@"unknown context state: " stringByAppendingString:name]);
    demand(!exists(at(root,@"controller.json")) && !exists(at(root,@"sentinel.txt")),@"unarchived case state; refusing replacement");
    demand(safeFixturePath(at(root,@"events")),@"unsafe events directory");
    demand([[[NSFileManager defaultManager] contentsOfDirectoryAtPath:at(root,@"events") error:NULL] count]==0,@"stale event records present");
}
static NSRunningApplication *readyProbe(void) {
    demand(fixturePrerequisites(contextProbe,contextRoot,at(contextRoot,@"events")),@"fixture prerequisites mismatch");
    NSRunningApplication *a=[[NSWorkspace sharedWorkspace] launchApplicationAtURL:contextProbe options:NSWorkspaceLaunchWithoutActivation configuration:@{} error:NULL];
    demand(owned(a,contextProbe),@"fixture launch identity mismatch");
    NSDictionary *s=waitRecordSnapshot(at(contextRoot,@"events"),a.processIdentifier,@[],@"finished-launching",12);
    demand([[s objectForKey:@"requirements_observed"] boolValue],@"fixture not ready before deadline"); return a;
}
static OSStatus permission(NSRunningApplication *a, BOOL ask) {
#if defined(__MAC_10_14) && __MAC_OS_X_VERSION_MIN_REQUIRED >= __MAC_10_14
    pid_t pid=a.processIdentifier;
    NSAppleEventDescriptor *target=[NSAppleEventDescriptor descriptorWithDescriptorType:typeKernelProcessID data:[NSData dataWithBytes:&pid length:sizeof(pid)]];
    return AEDeterminePermissionToAutomateTarget(target.aeDesc,'WPrb','ping',(Boolean)ask);
#else
    return -1; /* floor build: cannot establish no-prompt modern execution */
#endif
}
static NSDictionary *transport(NSRunningApplication *a, NSString *nonce) {
    NSString *payload=[@"transport-" stringByAppendingString:nonce];
    OSStatus status=-1; NSUInteger mode=0;
#if defined(__MAC_10_14) && __MAC_OS_X_VERSION_MIN_REQUIRED >= __MAC_10_14
    pid_t pid=a.processIdentifier;
    NSAppleEventDescriptor *target=[NSAppleEventDescriptor descriptorWithDescriptorType:typeKernelProcessID data:[NSData dataWithBytes:&pid length:sizeof(pid)]];
    NSAppleEventDescriptor *event=[NSAppleEventDescriptor appleEventWithEventClass:'WPrb' eventID:'ping' targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:payload] forKeyword:keyDirectObject];
    mode=kAENoReply|kAENeverInteract|kAEDoNotPromptForUserConsent;
    status=AESendMessage(event.aeDesc,NULL,(AESendMode)mode,60);
#endif
    NSTimeInterval end=[NSProcessInfo processInfo].systemUptime+12;
    NSArray *rs=@[]; BOOL delivered=NO;
    do {
        rs=records(at(contextRoot,@"events"),a.processIdentifier);
        delivered=customPayload(rs,payload);
        if(delivered || workspaceInterrupted)break;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }while([NSProcessInfo processInfo].systemUptime<end);
    return @{@"payload":payload,@"fixture_pid":@(a.processIdentifier),@"send_mode":@(mode),@"send_status":@(status),@"exact_payload_observed":@(delivered),@"records":rs,@"deadline_seconds":@12};
}
static NSArray *caseNames(void) {
    return [@"stopped reused multiple mixed new-instance startup reuse-configuration without-activation custom-event custom-reuse invalid-app nil-error nil-error-failure ownership empty empty-custom conflicting-event unknown-key impossible-architecture asynchronous architecture" componentsSeparatedByString:@" "];
}
@interface WorkspaceContextSender : NSObject <NSApplicationDelegate>
@end
@implementation WorkspaceContextSender
- (void)applicationDidFinishLaunching:(NSNotification *)note { [self performSelector:@selector(run) withObject:nil afterDelay:0.1]; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app { workspaceInterrupted=SIGTERM; if(contextOwnsFixture) clean(contextProbe); return NSTerminateNow; }
- (void)run {
    NSMutableDictionary *response=[NSMutableDictionary dictionaryWithObjectsAndKeys:@1,@"exit",@"cannot-measure",@"disposition",nil];
    NSString *report=nil; BOOL casesStarted=NO;
    @try {
        NSDictionary *request=load(at(contextRoot,@"request.json"));
        report=[request objectForKey:@"report"];
        demand([text(at(contextRoot,@"source.sha256")) isEqual:@CONTEXT_SOURCE_ID],@"sender source mismatch");
        demand([[load(at(contextRoot,@".run-lock/owner.json")) objectForKey:@"nonce"] isEqual:[request objectForKey:@"nonce"]],@"context lock/request mismatch");
        demand(safeFixturePath(report),@"unsafe report path");
        [response addEntriesFromDictionary:@{@"nonce":[request objectForKey:@"nonce"],@"sender_bundle_id":[NSBundle mainBundle].bundleIdentifier,@"sender_path":[NSBundle mainBundle].bundlePath,@"sender_pid":@(getpid()),@"fixture_bundle_id":[NSBundle bundleWithURL:contextProbe].bundleIdentifier,@"context":contextRoot,@"source_sha256":@CONTEXT_SOURCE_ID}];
        validateUnsignedState(contextRoot);
        demand(live(contextProbe).count==0,@"fixture already running");
        NSString *operation=[request objectForKey:@"operation"];
        contextOwnsFixture=YES;
        NSRunningApplication *probe=readyProbe();
        OSStatus preflight=permission(probe,NO);
        [response setObject:@(preflight) forKey:@"permission_preflight"];
        if([operation isEqual:@"authorize"]) {
            // This is the sole requesting branch; preparation/verification never use it.
            save(at(report,@"permission-before.json"),response);
            [response setObject:@(preflight==noErr ? noErr : permission(probe,YES)) forKey:@"permission_request"];
            [response setObject:@(permission(probe,NO)) forKey:@"permission_postflight"];
            [response setObject:@"permission-status-only-not-delivery" forKey:@"disposition"];
            [response setObject:@(permission(probe,NO)==noErr ? 0 : 1) forKey:@"exit"];
        } else if([operation isEqual:@"preflight"]) {
            [response setObject:@"nonprompt-permission-status-only" forKey:@"disposition"];
            [response setObject:@(preflight==noErr ? 0 : 1) forKey:@"exit"];
        } else {
            demand([operation isEqual:@"run"],@"unknown sender operation");
            demand(preflight==noErr,@"ungranted context: cannot measure (no prompt requested)");
            NSDictionary *t=transport(probe,[request objectForKey:@"nonce"]);
            save(at(report,@"transport.json"),t);
            demand([[t objectForKey:@"send_status"] intValue]==noErr && [[t objectForKey:@"exact_payload_observed"] boolValue],@"external transport control failed; permission zero is not delivery");
        }
        demand(clean(contextProbe),@"transport fixture cleanup failed");
        moveFresh(at(contextRoot,@"events"),at(report,@"preflight-events")); privateDirectory(at(contextRoot,@"events"));
        if([operation isEqual:@"run"]) {
            casesStarted=YES;
            NSMutableArray *matrix=[NSMutableArray array]; int status=0;
            for(NSString *name in caseNames()) {
                demand(!workspaceInterrupted,@"app-hosted run interrupted");
                validateUnsignedState(contextRoot);
                char *args[]={"reference",(char*)name.UTF8String,(char*)contextProbe.path.UTF8String,(char*)contextRoot.UTF8String,NULL};
                int rc=workspaceReferenceMain(4,args);
                demand(clean(contextProbe),@"case cleanup did not complete");
                archiveCase(contextRoot,report,name,rc);
                [matrix addObject:@{@"case":name,@"exit":@(rc)}];
                save(at(report,[@"progress-" stringByAppendingString:[name stringByAppendingString:@".json"]]),@{@"cases":matrix});
                if(rc!=0)status=1;
                if(rc==77 || workspaceInterrupted)break;
            }
            demand(matrix.count==21,@"incomplete case matrix");
            [response setObject:matrix forKey:@"cases"]; [response setObject:@(status) forKey:@"exit"];
            [response setObject:status ? @"failed" : @"assertions-passed-with-observations" forKey:@"disposition"];
        }
    } @catch(NSException *e) { [response setObject:e.reason ?: e.name forKey:@"failure"]; }
    [response setObject:@(!contextOwnsFixture || clean(contextProbe)) forKey:@"cleanup_completed"];
    // Permission/transport failure still archives unsigned readiness logs and
    // restores an empty events directory; it never changes the signed fixture.
    if(!casesStarted && report && !exists(at(report,@"preflight-events"))) @try {
        moveFresh(at(contextRoot,@"events"),at(report,@"preflight-events")); privateDirectory(at(contextRoot,@"events"));
    } @catch(NSException *e) { [response setObject:e.reason forKey:@"archive_failure"]; [response setObject:@1 forKey:@"exit"]; }
    if(workspaceInterrupted) { [response setObject:@(workspaceInterrupted) forKey:@"interrupted_signal"]; [response setObject:@1 forKey:@"exit"]; }
    @try { save(at(contextRoot,@"response.json"),response); } @catch(NSException *e) { fprintf(stderr,"sender cannot publish response\n"); }
    [NSApp terminate:nil];
}
@end
#ifdef WORKSPACE_CONTEXT_UNIT_TESTS
// Deliberately fixture-free app actors. These never query/request Automation.
@interface WorkspaceUnitActor : NSObject <NSApplicationDelegate>
@end
@implementation WorkspaceUnitActor
- (void)applicationDidFinishLaunching:(NSNotification *)note { [self performSelector:@selector(work) withObject:nil afterDelay:0.2]; }
- (void)work {
    NSString *dir=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"WorkspaceUnitDirectory"];
    save(at(dir,@"ready.json"),@{@"unit_only":@YES});
    if([[[NSBundle mainBundle] objectForInfoDictionaryKey:@"WorkspaceUnitMode"] isEqual:@"wait"]) {
        NSTimeInterval end=[NSProcessInfo processInfo].systemUptime+5;
        while(!workspaceInterrupted && [NSProcessInfo processInfo].systemUptime<end) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        save(at(dir,@"interrupted.json"),@{@"unit_only":@YES,@"signal":@(workspaceInterrupted)});
    }
    [NSApp terminate:nil];
}
@end
static void actorUnitTests(NSString *base) {
    for(NSString *mode in @[@"exit",@"wait"]) {
        NSString *dir=at(base,[@"unit-actor-" stringByAppendingString:mode]); privateDirectory(dir);
        NSString *app=at(dir,[mode isEqual:@"wait"] ? @"Probe.app" : @"Actor.app"); privateDirectory(app); privateDirectory(at(app,@"Contents")); privateDirectory(at(app,@"Contents/MacOS"));
        demand([[NSFileManager defaultManager] copyItemAtPath:[[[NSProcessInfo processInfo] arguments] objectAtIndex:0] toPath:at(app,@"Contents/MacOS/Actor") error:NULL],@"cannot copy unit actor");
        NSDictionary *plist=@{@"CFBundleIdentifier":[@"org.mavergreen.unit.actor." stringByAppendingString:[NSProcessInfo processInfo].globallyUniqueString],@"CFBundleExecutable":@"Actor",@"CFBundlePackageType":@"APPL",@"NSPrincipalClass":@"NSApplication",@"WorkspaceUnitDirectory":dir,@"WorkspaceUnitMode":mode};
        demand([plist writeToFile:at(app,@"Contents/Info.plist") atomically:YES],@"unit actor plist failed");
        NSTask *sign=[NSTask new]; sign.launchPath=@"/usr/bin/codesign"; sign.arguments=@[@"--force",@"--sign",@"-",app]; [sign launch];[sign waitUntilExit]; demand(sign.terminationStatus==0,@"unit actor signature failed");[sign release];
        NSURL *url=[NSURL fileURLWithPath:app];
        NSRunningApplication *actor=[[NSWorkspace sharedWorkspace] launchApplicationAtURL:url options:NSWorkspaceLaunchNewInstance|NSWorkspaceLaunchWithoutActivation configuration:@{} error:NULL];
        @try {
        demand(owned(actor,url),@"unit actor launch identity");
        NSTimeInterval end=[NSProcessInfo processInfo].systemUptime+3;
        while(!exists(at(dir,@"ready.json")) && !actor.terminated && [NSProcessInfo processInfo].systemUptime<end) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        demand(exists(at(dir,@"ready.json")),@"unit actor readiness");
        if([mode isEqual:@"wait"]) {
            // Overlap refusal must not clean another actor's live fixture. This
            // is a fixture-free unit actor deliberately named Probe.app.
            demand(acquire(dir),@"unit live lock acquisition");
            NSTask *overlap=[NSTask new]; overlap.launchPath=[[[NSProcessInfo processInfo] arguments] objectAtIndex:0];
            overlap.arguments=@[@"launch",dir,@"run",at(base,@"unit-overlap-report")];
            [overlap launch]; [overlap waitUntilExit];
            demand(overlap.terminationStatus==1 && !actor.terminated,@"lock refusal disrupted live actor"); [overlap release];
            demand(rmdir([at(dir,@".run-lock") fileSystemRepresentation])==0,@"unit live lock release");
            workspaceInterrupted=SIGTERM; // exercise verified forwarding in awaitActor
        }
        awaitActor(actor,url,6);
        if([mode isEqual:@"wait"]) demand([[load(at(dir,@"interrupted.json")) objectForKey:@"signal"] intValue]==SIGTERM,@"actor did not receive interruption");
        else {
            BOOL rejected=NO; @try { load(at(dir,@"response.json")); } @catch(NSException *e) { rejected=YES; }
            demand(rejected,@"actor exited without report but was accepted");
        }
        } @finally { clean(url); workspaceInterrupted=0; }
        demand(live(url).count==0,@"unit actor left alive");
    }
}
#endif
static int selfTest(NSString *base) {
    NSString *root=at(base,@"unit-context"), *out=at(base,@"unit-report"); privateDirectory(root); privateDirectory(out); privateDirectory(at(root,@"events"));
    demand(acquire(root),@"unit initial lock"); demand(!acquire(root),@"unit overlapping lock accepted");
    demand(rmdir([at(root,@".run-lock") fileSystemRepresentation])==0,@"unit lock release");
    validateUnsignedState(root);
    save(at(root,@"events/stale.json"),@{@"unit_only":@YES});
    BOOL refused=NO; @try{validateUnsignedState(root);}@catch(NSException *e){refused=YES;} demand(refused,@"stale events accepted");
    [[NSFileManager defaultManager] removeItemAtPath:at(root,@"events/stale.json") error:NULL];
    save(at(root,@"events/unit-evidence.json"),@{@"unit_nonce":@"first"});
    save(at(root,@"controller.json"),@{@"case":@"stopped",@"disposition":@"passed",@"cleanup_completed":@YES});
    archiveCase(root,out,@"stopped",0); validateUnsignedState(root);
    save(at(root,@"events/unit-evidence.json"),@{@"unit_nonce":@"second"});
    save(at(root,@"controller.json"),@{@"case":@"reused",@"disposition":@"passed",@"cleanup_completed":@YES});
    archiveCase(root,out,@"reused",0); validateUnsignedState(root);
    demand([[load(at(out,@"stopped/events/unit-evidence.json")) objectForKey:@"unit_nonce"] isEqual:@"first"] && [[load(at(out,@"reused/events/unit-evidence.json")) objectForKey:@"unit_nonce"] isEqual:@"second"],@"archive boundaries mixed stale evidence");
    demand(exists(at(out,@"stopped/controller.json")) && exists(at(out,@"stopped/events")),@"unit archive missing");
    save(at(root,@"controller.json"),@{@"case":@"stopped",@"disposition":@"passed",@"cleanup_completed":@YES});
    refused=NO;@try{archiveCase(root,out,@"stopped",0);}@catch(NSException *e){refused=YES;}demand(refused,@"archive output reused");
    demand(caseNames().count==21,@"case inventory incomplete");
    refused=NO;@try{load(at(root,@"missing-response.json"));}@catch(NSException *e){refused=YES;}demand(refused,@"missing actor response accepted");
    [@"{partial" writeToFile:at(root,@"partial-response.json") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    refused=NO;@try{load(at(root,@"partial-response.json"));}@catch(NSException *e){refused=YES;}demand(refused,@"partial actor response accepted");
    raise(SIGTERM); demand(workspaceInterrupted==SIGTERM,@"unit signal flag missing"); workspaceInterrupted=0;
#ifdef WORKSPACE_CONTEXT_UNIT_TESTS
    actorUnitTests(base);
#endif
    printf("UNIT/STUB ONLY: locks, stale isolation, archives, missing/partial reports, actor exit/interruption, 21 cases pass\n"); return 0;
}
int main(int argc,char **argv) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new]; installWorkspaceSignals(); int status=1;
#ifdef WORKSPACE_CONTEXT_UNIT_TESTS
    if([[NSBundle mainBundle] objectForInfoDictionaryKey:@"WorkspaceUnitDirectory"]) {
        NSApplication *app=[NSApplication sharedApplication]; WorkspaceUnitActor *delegate=[WorkspaceUnitActor new]; app.delegate=delegate; [app run]; [delegate release]; [pool drain]; return 0;
    }
#endif
    NSString *appRoot=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"WorkspaceContextDirectory"];
    if(appRoot) {
        contextRoot=[appRoot copy]; contextProbe=[[NSURL fileURLWithPath:at(contextRoot,@"Probe.app")] retain];
        NSApplication *app=[NSApplication sharedApplication]; [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        WorkspaceContextSender *delegate=[WorkspaceContextSender new]; app.delegate=delegate; [app run]; [delegate release];
        [pool drain];return 0;
    }
    BOOL locked=NO, ownsReport=NO, actorLaunchAttempted=NO; NSString *report=nil; NSRunningApplication *actor=nil;
    @try {
        demand(argc>=3,@"usage: context-driver describe|self-test ROOT | launch ROOT OP NEW_REPORT");
        contextRoot=[[NSString stringWithUTF8String:argv[2]] copy]; contextProbe=[[NSURL fileURLWithPath:at(contextRoot,@"Probe.app")] retain];
        NSString *command=[NSString stringWithUTF8String:argv[1]];
        if([command isEqual:@"self-test"]) { status=selfTest(contextRoot); goto done; }
        if([command isEqual:@"describe"]) {
            NSDictionary *d=@{@"context":contextRoot,@"source_sha256":@CONTEXT_SOURCE_ID,@"sender_path":at(contextRoot,@"Sender.app"),@"sender_executable":at(contextRoot,@"Sender.app/Contents/MacOS/WorkspaceSender"),@"sender_bundle_id":[NSBundle bundleWithPath:at(contextRoot,@"Sender.app")].bundleIdentifier,@"fixture_path":contextProbe.path,@"fixture_executable":at(contextRoot,@"Probe.app/Contents/MacOS/WorkspaceProbe"),@"fixture_bundle_id":[NSBundle bundleWithURL:contextProbe].bundleIdentifier,@"permission_requested":@NO};
            NSMutableDictionary *manifest=[NSMutableDictionary dictionaryWithDictionary:d];
            [manifest addEntriesFromDictionary:@{@"source_commit":text(at(contextRoot,@"source.commit")),@"architecture":text(at(contextRoot,@"architecture")),@"sdk_path":text(at(contextRoot,@"sdk.path")),@"sdk_settings_sha256":text(at(contextRoot,@"sdk.sha256")),@"compiler":text(at(contextRoot,@"compiler.txt")),@"sender_display_name":[[NSBundle bundleWithPath:at(contextRoot,@"Sender.app")] objectForInfoDictionaryKey:@"CFBundleDisplayName"],@"fixture_display_name":[[NSBundle bundleWithURL:contextProbe] objectForInfoDictionaryKey:@"CFBundleDisplayName"],@"possible_os_fallback_names":@[@"Sender.app",@"WorkspaceProbe"],@"deployment_target_numeric":@(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__)}];
            save(at(contextRoot,@"preparation.json"),manifest); status=0;goto done;
        }
        demand([command isEqual:@"launch"] && argc==5,@"invalid driver invocation");
        demand(safeFixturePath(contextRoot),@"unsafe context root");
        report=[NSString stringWithUTF8String:argv[4]];
        if(!report.isAbsolutePath) report=[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:report];
        NSString *physicalReport=[canonicalFixturePath([report stringByDeletingLastPathComponent]) stringByAppendingPathComponent:[report lastPathComponent]];
        demand(physicalReport && ![physicalReport isEqual:contextRoot] && ![physicalReport hasPrefix:[contextRoot stringByAppendingString:@"/"]],@"results must be outside stable context");
        privateDirectory(report); ownsReport=YES; demand(safeFixturePath(report),@"unsafe result directory");
        demand(acquire(contextRoot),@"context is locked (never break a lock from a PID log)"); locked=YES;
        demand(!exists(at(contextRoot,@"request.json")) && !exists(at(contextRoot,@"response.json")),@"unfinished prior control operation");
        validateUnsignedState(contextRoot);
        NSURL *sender=[NSURL fileURLWithPath:at(contextRoot,@"Sender.app")]; demand(live(sender).count==0,@"sender already running");
        NSString *nonce=[NSProcessInfo processInfo].globallyUniqueString;
        save(at(contextRoot,@".run-lock/owner.json"),@{@"nonce":nonce,@"launcher_pid":@(getpid()),@"report":report});
        save(at(contextRoot,@"request.json"),@{@"nonce":nonce,@"operation":[NSString stringWithUTF8String:argv[3]],@"report":report});
        demand(live(contextProbe).count==0,@"fixture already running before this operation");
        actorLaunchAttempted=YES;
        actor=[[NSWorkspace sharedWorkspace] launchApplicationAtURL:sender options:NSWorkspaceLaunchNewInstance configuration:@{} error:NULL];
        demand(owned(actor,sender),@"app-hosted sender launch failed");
        awaitActor(actor,sender,900);
        NSDictionary *response=load(at(contextRoot,@"response.json"));
        demand([[response objectForKey:@"nonce"] isEqual:nonce] && [[response objectForKey:@"cleanup_completed"] boolValue],@"stale/malformed response or cleanup failure");
        id returnedExit=[response objectForKey:@"exit"];
        demand([returnedExit isKindOfClass:[NSNumber class]] && ([returnedExit intValue]==0 || [returnedExit intValue]==1) && [[response objectForKey:@"disposition"] isKindOfClass:[NSString class]],@"incomplete actor response schema");
        status=[returnedExit intValue];
        if(status==0 && [[NSString stringWithUTF8String:argv[3]] isEqual:@"run"]) demand([[response objectForKey:@"cases"] count]==21,@"successful response omitted cases");
        moveFresh(at(contextRoot,@"response.json"),at(report,@"response.json"));
        moveFresh(at(contextRoot,@"request.json"),at(report,@"request.json"));
        if(workspaceInterrupted) { save(at(report,@"launcher-interrupted.json"),@{@"signal":@(workspaceInterrupted),@"exit":@1}); status=1; }
    } @catch(NSException *e) {
        fprintf(stderr,"context failure: %s\n",e.reason.UTF8String);
        // Never disrupt another operation when we merely refused its held lock.
        if(actorLaunchAttempted) {
            clean([NSURL fileURLWithPath:at(contextRoot,@"Sender.app")]);
            clean(contextProbe);
        }
        if(ownsReport && !exists(at(report,@"launcher-failure.json"))) @try { save(at(report,@"launcher-failure.json"),@{@"failure":e.reason ?: e.name,@"exit":@1}); }@catch(NSException *ignored){}
        status=1;
    }
done:
    if(locked) { unlink([at(contextRoot,@".run-lock/owner.json") fileSystemRepresentation]); rmdir([at(contextRoot,@".run-lock") fileSystemRepresentation]); }
    [contextProbe release];[contextRoot release];[pool drain];return status;
}
