/* Actual registered-method integration: original21 assertions unchanged.
 * Additional floor cases use only owned fixtures. No default handlers/grants. */
#define WORKSPACE_OPTIONS_NO_MAIN 1
#include "objc_workspace_options_reference.m"
#include <sys/wait.h>
static BOOL integrationPin(NSString *root) {
    if (!safeFixturePath(root)) return NO;
    int fd=open(root.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW); struct stat s;
    BOOL ok=fd>=0 && !fstat(fd,&s) && S_ISDIR(s.st_mode) && s.st_uid==geteuid() && !(s.st_mode&077) && !fchdir(fd);
    if (fd>=0) close(fd); return ok;
}
static BOOL integrationJSON(NSString *name,id value) {
    int fd=open(name.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if (fd<0) return NO;
    BOOL ok=optionsWrite(fd,[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:NULL]);
    return close(fd)==0 && ok;
}
static NSDictionary *integrationCall(OptionsCall *call) {
    return @{@"returned_pid":@(call->returned.processIdentifier),@"returned_bundle_url":call->returned.bundleURL.absoluteString ?: (id)[NSNull null],
        @"executable_architecture":@(call->returned.executableArchitecture),@"finished_launching_at_return":@(call->returned.finishedLaunching),@"call_on_main_thread":@(call->mainThread),
        @"error_domain":call->error.domain ?: (id)[NSNull null],@"error_code":call->error ? @(call->error.code):(id)[NSNull null],
        @"exception":call->exception ?: (id)[NSNull null],@"options":@(call->flags),@"duration_seconds":@(call->duration)};
}
static int integrationFloor(int argc,char **argv,BOOL child) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new]; installWorkspaceSignals();
    NSString *name=[NSString stringWithUTF8String:argv[2]], *root=[NSString stringWithUTF8String:argv[4]];
    NSString *input=[NSString stringWithUTF8String:argv[3]];
    NSURL *app=[input isAbsolutePath] ? [NSURL fileURLWithPath:input]:[NSURL URLWithString:input];
    NSString *events=[root stringByAppendingPathComponent:@"events"];
    NSArray *known=@[@"i386-selection",@"i386-reuse",@"i386-new-instance",@"worker",@"async-caller-exit",@"ls-mixed"];
    if (![known containsObject:name] || !integrationPin(root) || !fixturePrerequisites(app,root,events) ||
        !class_getInstanceMethod([NSWorkspace class],@selector(openURLs:withApplicationAtURL:options:configuration:error:))) { [pool drain]; return 1; }
    NSString *nonce=child ? [NSString stringWithContentsOfFile:@"nonce.txt" encoding:NSUTF8StringEncoding error:NULL] : [[NSProcessInfo processInfo] globallyUniqueString];
    if (!nonce.length) { [pool drain]; return 1; }
    if (!child) {
        int fd=open("nonce.txt",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
        if (fd<0) { [pool drain]; return 1; }
        BOOL ok=optionsWrite(fd,[nonce dataUsingEncoding:NSUTF8StringEncoding]); if (close(fd) || !ok) { [pool drain]; return 1; }
    }
    NSURL *url=[NSURL URLWithString:[@"https://workspace-floor.invalid/payload/" stringByAppendingString:nonce]];
    NSURL *second=[NSURL URLWithString:[@"https://workspace-floor.invalid/second/" stringByAppendingString:nonce]];
    BOOL multiple=[name isEqual:@"worker"] || [name isEqual:@"async-caller-exit"];
    OptionsCall call; memset(&call,0,sizeof(call)); call.workspace=[NSWorkspace sharedWorkspace]; call.urls=multiple ? @[url,second]:@[url]; call.app=app;
    call.flags=NSWorkspaceLaunchWithoutActivation;
    /* ls-mixed: no architecture, so the Launch Services path; a document plus
     * two URLs, opened WithoutAddingToRecents so Recent Documents is untouched. */
    if ([name isEqual:@"ls-mixed"]) {
        if (!child) {
            int fd=open("floor-document.txt",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
            if (fd<0) { [pool drain]; return 1; }
            BOOL ok=optionsWrite(fd,[@"floor document" dataUsingEncoding:NSUTF8StringEncoding]); if (close(fd) || !ok) { [pool drain]; return 1; }
        }
        call.urls=@[[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"floor-document.txt"]],url,second];
        call.flags|=NSWorkspaceLaunchWithoutAddingToRecents;
    }
    NSArray *arguments=@[@"--floor-sentinel",@"exact floor argv"];
    NSString *environment=@"exact floor environment";
    NSMutableDictionary *cfg=[NSMutableDictionary dictionaryWithObjectsAndKeys:arguments,NSWorkspaceLaunchConfigurationArguments,
        @{@"WORKSPACE_PROBE_SENTINEL":environment},NSWorkspaceLaunchConfigurationEnvironment,nil];
    call.configuration=cfg;
    BOOL is386=[name hasPrefix:@"i386-"], reuse=[name isEqual:@"i386-reuse"], fresh=[name isEqual:@"i386-new-instance"];
    if (is386) [cfg setObject:@(NSBundleExecutableArchitectureI386) forKey:NSWorkspaceLaunchConfigurationArchitecture];
    if (fresh) call.flags|=NSWorkspaceLaunchNewInstance;
    if ([name isEqual:@"worker"] || [name isEqual:@"async-caller-exit"]) call.flags|=NSWorkspaceLaunchAsync;
    if (child) {
        optionsInvoke(&call); /* No NSRunLoop, no wait for application finish. */
        BOOL ok=owned(call.returned,app) && !call.exception && integrationJSON(@"caller.json",
            @{@"caller_pid":@(getpid()),@"call":integrationCall(&call),@"returned_before_exit":@YES});
        /* Explicit immediate caller exit: even pool/atexit cleanup cannot pump. */
        _exit(ok ? 0:1);
    }
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithObjectsAndKeys:name,@"case",nonce,@"nonce",url.absoluteString,@"requested_url",
        @"real rooted method; bounded observation only; no caller-created loop during worker/caller call",@"scope",nil];
    [result setObject:[call.urls valueForKey:@"absoluteString"] forKey:@"requested_urls"];
    NSMutableArray *failures=[NSMutableArray array], *cleanup=[NSMutableArray array];
    OptionsCall seed; memset(&seed,0,sizeof(seed));
    @try {
        if (reuse || fresh) {
            NSURL *seedURL=[NSURL URLWithString:[@"https://workspace-floor.invalid/seed/" stringByAppendingString:nonce]];
            seed.workspace=call.workspace; seed.urls=@[seedURL]; seed.app=app; seed.flags=NSWorkspaceLaunchWithoutActivation;
            seed.configuration=@{NSWorkspaceLaunchConfigurationArguments:@[@"--seed-x86_64"],NSWorkspaceLaunchConfigurationEnvironment:@{@"WORKSPACE_PROBE_SENTINEL":@"seed environment"},NSWorkspaceLaunchConfigurationArchitecture:@(NSBundleExecutableArchitectureX86_64)};
            optionsInvoke(&seed);
            if (owned(seed.returned,app)) [cleanup addObject:seed.returned];
            NSDictionary *snapshot=optionsSnapshot(events,seed.returned.processIdentifier,seed.urls,NO,NO);
            [result setObject:snapshot forKey:@"seed_observation"]; [result setObject:integrationCall(&seed) forKey:@"seed_call"];
            workspaceCheck(owned(seed.returned,app) && [[snapshot objectForKey:@"requirements_observed"] boolValue],@"seed exact private PID delivered payload",failures);
            workspaceCheck(seed.returned.executableArchitecture==NSBundleExecutableArchitectureX86_64,@"seed actually x86_64",failures);
        }
        if ([name isEqual:@"async-caller-exit"]) {
            NSTask *task=[[[NSTask alloc] init] autorelease]; task.launchPath=[NSString stringWithUTF8String:argv[0]];
            task.arguments=@[@"async-child",name,app.path,root]; [task launch]; [task waitUntilExit];
            [result setObject:@(task.terminationStatus) forKey:@"caller_exit_status"];
            workspaceCheck(task.terminationStatus==0,@"real asynchronous API caller exited successfully before supervisor observation",failures);
            /* Fixed owned path only; child input was validated before execution. */
            NSData *raw=[NSData dataWithContentsOfFile:@"caller.json"];
            NSDictionary *reply=raw ? [NSJSONSerialization JSONObjectWithData:raw options:0 error:NULL]:nil;
            if (![reply isKindOfClass:[NSDictionary class]]) [NSException raise:@"EvidenceFailure" format:@"missing complete caller receipt"];
            [result setObject:reply forKey:@"caller_exit_receipt"]; [result setObject:[reply objectForKey:@"call"] forKey:@"call"];
            pid_t pid=[[[reply objectForKey:@"call"] objectForKey:@"returned_pid"] intValue];
            call.returned=[[NSRunningApplication runningApplicationWithProcessIdentifier:pid] retain];
            workspaceCheck(pid>0 && pid!=[[reply objectForKey:@"caller_pid"] intValue],@"app and exited caller have distinct real PIDs",failures);
        } else if ([name isEqual:@"worker"]) {
            pthread_t thread; int rc=pthread_create(&thread,NULL,optionsInvoke,&call);
            if (rc) [NSException raise:@"ThreadFailure" format:@"pthread_create %d",rc];
            rc=pthread_join(thread,NULL); if (rc) [NSException raise:@"ThreadFailure" format:@"pthread_join %d",rc];
            workspaceCheck(!call.mainThread,@"method invoked off main thread without caller loop",failures);
        } else optionsInvoke(&call);
        if (![name isEqual:@"async-caller-exit"]) [result setObject:integrationCall(&call) forKey:@"call"];
        workspaceCheck(!call.exception && owned(call.returned,app),@"returned application is exact private fixture",failures);
        if (owned(call.returned,app) && ![cleanup containsObject:call.returned]) [cleanup addObject:call.returned];
        pid_t pid=call.returned.processIdentifier;
        NSDictionary *snapshot=optionsSnapshot(events,pid,call.urls,NO,NO); [result setObject:snapshot forKey:@"observation"];
        workspaceCheck([[snapshot objectForKey:@"requirements_observed"] boolValue],@"exact external payload/startup at actual system-selected PID",failures);
        NSArray *rs=[snapshot objectForKey:@"records"];
        NSString *arch=is386 && !reuse ? @"i386":@"x86_64";
        for (NSDictionary *r in rs) if ([[r objectForKey:@"kind"] isEqual:@"startup"]) {
            workspaceCheck([[r objectForKey:@"architecture"] isEqual:arch],@"recorded actual requested/reused executable architecture",failures);
            workspaceCheck(startupMatches(r,reuse ? @[@"--seed-x86_64"]:arguments,reuse ? @"seed environment":environment),@"exact startup argv/environment including reuse preservation",failures);
        }
        if (is386) workspaceCheck(call.returned.executableArchitecture==(reuse ? NSBundleExecutableArchitectureX86_64:NSBundleExecutableArchitectureI386),@"public running-app actual architecture agrees",failures);
        if (reuse || fresh) workspaceCheck(reuse ? pid==seed.returned.processIdentifier : pid!=seed.returned.processIdentifier,@"actual reuse/new-instance PID relation",failures);
        if (fresh) workspaceCheck(!contains(records(events,seed.returned.processIdentifier),@"open",url.absoluteString),@"new-instance URL did not leak to seed PID during checked interval",failures);
    } @catch (NSException *e) { [result setObject:@{@"name":e.name,@"reason":e.reason ?: @""} forKey:@"harness_exception"]; [failures addObject:@"floor harness failure (cannot measure)"]; }
    @finally {
        for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications]) if (owned(a,app) && ![cleanup containsObject:a]) [cleanup addObject:a];
        BOOL complete=YES;
        for (NSRunningApplication *a in cleanup) if (owned(a,app)) {
            [a terminate]; NSTimeInterval end=[[NSProcessInfo processInfo] systemUptime]+3;
            while (!a.terminated && [[NSProcessInfo processInfo] systemUptime]<end) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            if (!a.terminated && owned(a,app)) [a forceTerminate];
            end=[[NSProcessInfo processInfo] systemUptime]+3;
            while (!a.terminated && [[NSProcessInfo processInfo] systemUptime]<end) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            complete &= a.terminated;
        }
        [result setObject:@(complete) forKey:@"cleanup_completed"]; workspaceCheck(complete,@"owned fixture cleanup completed",failures);
    }
    [result setObject:failures forKey:@"failures"]; [result setObject:failures.count ? @"failed":@"passed" forKey:@"disposition"];
    BOOL written=integrationJSON(@"controller.json",result);
    [call.returned release]; [call.error release]; [call.exception release]; [seed.returned release]; [seed.error release]; [seed.exception release];
    int rc=(!written || failures.count) ? 1:0; [pool drain]; return rc;
}
int main(int argc,char **argv) {
    if (argc==5 && (!strcmp(argv[1],"floor-controls") || !strcmp(argv[1],"async-child"))) return integrationFloor(argc,argv,!strcmp(argv[1],"async-child"));
    return workspaceOriginalReferenceMain(argc,argv);
}
