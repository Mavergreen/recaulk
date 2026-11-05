/* Real backend/planner, recording per-call launch/lookup/send/note boundaries.
 * No method registration, application launch, history mutation or global hook. */
#import "../../src/objc/workspace-private.h"
#include <errno.h>
#include <string.h>
static int failures, deallocated, launches, lookups, notes, failLaunch, noLaunchError, failLookup, wrongPID, failSendAt, failNote, mutate;
static NSDictionary *captured;
static NSMutableArray *sent;
static NSArray *noted;
static NSWorkspaceLaunchOptions seenFlags;
static NSURL *app;
@interface RecordedRunning : NSObject
@property pid_t processIdentifier;
@property(retain) NSURL *bundleURL;
@property NSInteger executableArchitecture;
@end
@implementation RecordedRunning
- (void)dealloc { deallocated++; [_bundleURL release]; [super dealloc]; }
@end
static NSRunningApplication *running(pid_t pid, BOOL complete) {
    RecordedRunning *r=[[[RecordedRunning alloc] init] autorelease];
    r.processIdentifier=pid; r.bundleURL=complete ? app : nil; r.executableArchitecture=complete ? NSBundleExecutableArchitectureX86_64 : -1;
    return (NSRunningApplication *)r;
}
static NSRunningApplication *launch(NSWorkspace *w, NSURL *a, NSWorkspaceLaunchOptions flags, NSDictionary *cfg, NSError **e) {
    launches++; [captured release]; captured=[cfg retain]; seenFlags=flags;
    if (mutate) {
        [(NSMutableDictionary *)cfg setObject:@"private" forKey:@"injected-by-launch"];
        [[cfg objectForKey:NSWorkspaceLaunchConfigurationAppleEvent] setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"changed"] forKeyword:'mark'];
    }
    if (failLaunch) { if (!noLaunchError && e) *e=[NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil]; return nil; }
    return running(4242, NO);
}
static NSRunningApplication *lookup(pid_t pid) { lookups++; return failLookup ? nil : running(wrongPID ? 777 : pid, YES); }
static OSStatus sendEvent(NSAppleEventDescriptor *e) { [sent addObject:[[e copy] autorelease]]; return sent.count==(NSUInteger)failSendAt ? -1712 : 0; }
static BOOL note(NSArray *files, NSWorkspaceLaunchOptions flags, NSError **e) {
    notes++; noted=files;
    if (failNote) { if (e) *e=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]; return NO; }
    return YES;
}
static const RecaulkWorkspaceOps ops={launch,lookup,sendEvent,note};
static int lsCalls, lsStatus;
static NSArray *lsURLs, *lsArguments;
static NSDictionary *lsEnvironment;
static NSAppleEventDescriptor *lsInitial;
static LSLaunchFlags lsFlags;
static OSStatus lsOpen(NSArray *urls, NSURL *a, LSLaunchFlags flags, NSDictionary *environment, NSArray *arguments, NSAppleEventDescriptor *initial, pid_t *pid) {
    lsCalls++; lsURLs=urls; lsFlags=flags; lsEnvironment=environment; lsArguments=arguments; lsInitial=initial;
    if (lsStatus) return lsStatus;
    *pid=4242; return noErr;
}
static const RecaulkWorkspaceOps lsOps={launch,lookup,sendEvent,note,lsOpen};
static void lsReset(void) { lsCalls=lsStatus=0; lsURLs=lsArguments=nil; lsEnvironment=nil; lsInitial=nil; lsFlags=0; }
static void reset(void) {
    [captured release]; captured=nil; sent=[NSMutableArray array]; noted=nil;
    launches=lookups=notes=failLaunch=noLaunchError=failLookup=wrongPID=failSendAt=failNote=mutate=0;
}
#define CHECK(x, name) do { if (!(x)) { printf("FAIL line%d: %s\n",__LINE__,name); failures++; } } while (0)
static NSRunningApplication *openURLs(NSArray *urls, NSWorkspaceLaunchOptions flags, NSDictionary *cfg, NSError **e) {
    return recaulk_workspace_open_urls_with_ops(nil, urls, app, flags, cfg, e, &ops);
}
static pid_t addressedPID(NSAppleEventDescriptor *event) {
    NSAppleEventDescriptor *d=[event attributeDescriptorForKeyword:keyAddressAttr]; pid_t p=0;
    if (d.descriptorType==typeKernelProcessID && d.data.length==sizeof(p)) memcpy(&p,d.data.bytes,sizeof(p));
    return p;
}
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    app=[NSURL fileURLWithPath:@"/private/recording-only/Probe.app"];
    NSURL *web=[NSURL URLWithString:@"https://one.invalid/"], *web2=[NSURL URLWithString:@"https://two.invalid/"];
    NSURL *file=[NSURL fileURLWithPath:@"/private/owned-one.txt"], *file2=[NSURL fileURLWithPath:@"/private/owned-two.txt"];
    NSError *e=nil;
    NSMutableDictionary *cfg=[NSMutableDictionary dictionaryWithDictionary:@{NSWorkspaceLaunchConfigurationArguments:@[@"--owned"],NSWorkspaceLaunchConfigurationEnvironment:@{@"TOKEN":@"fixture-only"},NSWorkspaceLaunchConfigurationArchitecture:@(NSBundleExecutableArchitectureI386),@"unknown-future-key":@7}];
    reset(); NSWorkspaceLaunchOptions flags=NSWorkspaceLaunchAsync|NSWorkspaceLaunchNewInstance|NSWorkspaceLaunchAndHideOthers|NSWorkspaceLaunchWithErrorPresentation;
    NSRunningApplication *result=openURLs(@[web,web2],flags,cfg,&e);
    CHECK(result.processIdentifier==4242 && result.bundleURL && !e,"populated lookup identity returned without finish wait");
    CHECK(captured!=cfg && cfg.count==4 && ![cfg objectForKey:NSWorkspaceLaunchConfigurationAppleEvent],"caller config not mutated");
    CHECK(seenFlags==flags,"all flag bits, including UI-only flags, forwarded without effects in unit");
    for (id key in cfg) CHECK([[captured objectForKey:key] isEqual:[cfg objectForKey:key]],"all configuration keys forwarded");
    CHECK([[captured objectForKey:NSWorkspaceLaunchConfigurationAppleEvent] eventID]==kAEGetURL && sent.count==1 && addressedPID([sent objectAtIndex:0])==4242 && notes==0,"first GURL injected, remainder PID-targeted; browser-only no history");
    reset(); NSAppleEventDescriptor *custom=[NSAppleEventDescriptor appleEventWithEventClass:'RvTr' eventID:'Work' targetDescriptor:nil returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [custom setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"original"] forKeyword:'mark'];
    [cfg setObject:custom forKey:NSWorkspaceLaunchConfigurationAppleEvent]; mutate=1;
    result=openURLs(@[web,web2],0,cfg,&e);
    CHECK(result && sent.count==2 && ![cfg objectForKey:@"injected-by-launch"] && [[[custom paramDescriptorForKeyword:'mark'] stringValue] isEqual:@"original"],"custom event copied, preserved against launch mutation; all URLs sent");
    for (NSAppleEventDescriptor *event in sent) CHECK(addressedPID(event)==4242,"custom URL leg targets selected PID");
    reset(); NSArray *events=recaulk_workspace_url_events(@[file,web,file2,web2],0,&e);
    CHECK(events.count==3 && [[events objectAtIndex:0] eventID]==kAEOpenDocuments && [[[events objectAtIndex:0] paramDescriptorForKeyword:keyDirectObject] numberOfItems]==2,"all files grouped first");
    events=recaulk_workspace_url_events(@[file,file2],NSWorkspaceLaunchAndPrint,&e);
    CHECK(events.count==1 && [[events objectAtIndex:0] eventID]==kAEPrintDocuments && [[[events objectAtIndex:0] paramDescriptorForKeyword:keyDirectObject] numberOfItems]==2,"recording-only print plan groups both files");
    reset(); result=openURLs(@[file,web,file2],0,nil,&e);
    CHECK((result && notes==1 && [noted isEqual:@[file,file2]]),"only requested files noted after queues");
    reset(); result=openURLs(@[file],NSWorkspaceLaunchWithoutAddingToRecents,nil,&e);
    CHECK(result && notes==0,"suppression avoids note boundary entirely");
    reset(); failLaunch=1; e=nil;
    CHECK(!openURLs(@[web,web2],0,nil,&e) && e.code==ENOENT && !lookups && !sent.count && !notes,"launch failure propagates without sends");
    reset(); failLaunch=noLaunchError=1; e=nil;
    CHECK(!openURLs(@[web],0,nil,&e) && e,"missing delegated error is useful failure, not success");
    reset(); failLookup=1; e=nil;
    CHECK(!openURLs(@[web,web2],0,nil,&e) && e && !sent.count && !notes,"unavailable reacquisition never uses original provisional object");
    reset(); wrongPID=1; e=nil;
    CHECK(!openURLs(@[web,web2],0,nil,&e) && e && !sent.count,"wrong lookup PID is not selected for delivery");
    reset(); failSendAt=2; e=nil;
    CHECK(!openURLs(@[file,web,web2],0,nil,&e) && [e.domain isEqual:NSOSStatusErrorDomain] && e.code==-1712 && sent.count==2 && !notes,"partial send failure useful, no false bookkeeping success");
    reset(); failNote=1; e=nil;
    CHECK(!openURLs(@[file,web],0,nil,&e) && e && notes==1 && sent.count==1,"bookkeeping failure explicit after partial side effects");
    reset(); e=nil;
    CHECK(!openURLs(@[],0,nil,&e) && launches==1 && [e.domain isEqual:NSCocoaErrorDomain] && e.code==256,"originally empty input preserves launch then nil/Cocoa256");
    reset(); CHECK(!openURLs(@[],0,nil,NULL),"nil error pointer safe");
    reset(); e=nil; result=openURLs(@[@"not an NSURL"],0,nil,&e);
    CHECK(result && !e && launches==1 && !sent.count && ![captured objectForKey:NSWorkspaceLaunchConfigurationAppleEvent],"nonempty invalid-element observation launches default event, not empty error");
    reset(); result=openURLs(@[[NSURL URLWithString:@"relative/item"]],0,nil,&e);
    CHECK(result && [[[[captured objectForKey:NSWorkspaceLaunchConfigurationAppleEvent] paramDescriptorForKeyword:keyDirectObject] stringValue] isEqual:@"relative/item"],"relative NSURL kept verbatim");
    reset(); BOOL raised=NO;
    @try { openURLs(nil,0,nil,NULL); } @catch(NSException *x) { raised=[x.name isEqual:NSInternalInconsistencyException]; }
    CHECK(raised && !launches,"nil urls observed precondition before launch");
    reset(); raised=NO;
    @try { openURLs(@[web],0,(id)@"not a dictionary",NULL); } @catch(NSException *x) { raised=[x.name isEqual:NSInvalidArgumentException]; }
    CHECK(raised && !launches,"malformed configuration explicit precondition, no accidental messages");
    reset(); NSAutoreleasePool *inner=[NSAutoreleasePool new];
    NSRunningApplication *kept=[openURLs(@[web],0,nil,NULL) retain]; [inner drain]; int before=deallocated;
    CHECK(kept.processIdentifier==4242,"explicit caller retain survives pool"); [kept release];
    CHECK(deallocated==before+1,"+0 result has no hidden provider retain");
    reset(); inner=[NSAutoreleasePool new]; failLaunch=1; e=nil; openURLs(@[web],0,nil,&e); NSError *ownedError=[e retain]; [inner drain];
    CHECK(ownedError.code==ENOENT && ownedError.localizedDescription.length,"caller-retained +0 error survives pool"); [ownedError release];
    reset(); e=[NSError errorWithDomain:@"sentinel" code:1 userInfo:nil]; NSError *sentinel=e;
    CHECK(openURLs(@[web],0,nil,&e) && e==sentinel,"success leaves optional error output untouched");
    /* Launch Services path: one request carries every URL and the configuration. */
    #define LSOPEN(u,f,c,err) recaulk_workspace_open_urls_with_ops(nil,(u),app,(f),(c),(err),&lsOps)
    reset(); lsReset(); e=nil;
    NSAppleEventDescriptor *lsCustom=[NSAppleEventDescriptor appleEventWithEventClass:'RvTr' eventID:'Work' targetDescriptor:nil returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    NSDictionary *lsConfig=@{NSWorkspaceLaunchConfigurationArguments:@[@"--owned"],NSWorkspaceLaunchConfigurationEnvironment:@{@"TOKEN":@"fixture-only"},NSWorkspaceLaunchConfigurationAppleEvent:lsCustom};
    result=LSOPEN((@[file,web,file2,web2]),NSWorkspaceLaunchWithoutActivation|NSWorkspaceLaunchNewInstance,lsConfig,&e);
    CHECK(result.processIdentifier==4242 && !e && lsCalls==1 && [lsURLs isEqual:(@[file,web,file2,web2])],"LS path: one request carries every URL in order");
    CHECK(lsFlags==(kLSLaunchDontSwitch|kLSLaunchNewInstance),"LS path: shared flag bits forwarded unchanged");
    CHECK([lsArguments isEqual:@[@"--owned"]] && [lsEnvironment isEqual:@{@"TOKEN":@"fixture-only"}],"LS path: arguments and environment forwarded");
    CHECK(lsInitial && lsInitial!=lsCustom && lsInitial.eventClass=='RvTr',"LS path: caller's initial event copied, not reused");
    CHECK(!launches && !sent.count && !notes,"LS path: no legacy launch, no own sends, no own Recents bookkeeping");
    reset(); lsReset(); e=nil; failLookup=1;
    CHECK(!LSOPEN((@[web,web2]),0,nil,&e) && e.code==ESRCH && lsCalls==1 && lsURLs.count==2,"LS path: identity failure reported after every URL was handed to LS");
    reset(); lsReset(); e=nil; lsStatus=fnfErr;
    CHECK(!LSOPEN(@[web],0,nil,&e) && [e.domain isEqual:NSCocoaErrorDomain] && e.code==NSFileReadNoSuchFileError && !lookups,"LS path: missing application is Cocoa 260, as natively");
    reset(); lsReset(); e=nil; lsStatus=kLSUnknownErr;
    CHECK(!LSOPEN(@[web],0,nil,&e) && [e.domain isEqual:NSOSStatusErrorDomain] && e.code==kLSUnknownErr && !lookups,"LS path: other LS failures propagate as OSStatus errors, no lookup");
    reset(); lsReset(); e=nil;
    CHECK(!LSOPEN(@[],0,nil,&e) && lsCalls==1 && !lsURLs.count && [e.domain isEqual:NSCocoaErrorDomain] && e.code==256,"LS path: empty input launches, then nil/Cocoa256");
    reset(); lsReset(); e=nil;
    result=LSOPEN((@[web,web2]),0,(@{NSWorkspaceLaunchConfigurationArchitecture:@(NSBundleExecutableArchitectureI386)}),&e);
    CHECK(result && !lsCalls && launches==1 && sent.count==1,"architecture request keeps the launch-then-send path");
    reset(); lsReset(); raised=NO;
    @try { LSOPEN(@[web],0,(@{NSWorkspaceLaunchConfigurationEnvironment:@"not a dictionary"}),NULL); } @catch(NSException *x) { raised=[x.name isEqual:NSInvalidArgumentException]; }
    CHECK(raised && !lsCalls,"LS path: malformed environment is an explicit precondition");
    [captured release]; captured=nil;
    printf("%s: real backend/planner with per-call recording boundaries; not external delivery proof\n", failures ? "FAIL":"PASS");
    [pool drain]; return failures ? 1:0;
}
