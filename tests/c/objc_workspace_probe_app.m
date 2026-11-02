/* Private Launch Services fixture: 10.9-compatible event hooks, no external actions. */
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <unistd.h>
static NSString *directory;
static NSUInteger sequence;
static void record(NSString *kind, NSDictionary *fields) {
    NSMutableDictionary *r = [NSMutableDictionary dictionaryWithDictionary:fields ?: @{}];
    [r addEntriesFromDictionary:@{@"kind": kind, @"pid": @(getpid()), @"sequence": @(sequence++)}];
    NSData *d = [NSJSONSerialization dataWithJSONObject:r options:0 error:NULL];
    NSString *p = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.jsonl", getpid()]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:p]) [[NSFileManager defaultManager] createFileAtPath:p contents:nil attributes:nil];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    [h seekToEndOfFile]; [h writeData:d]; [h writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile];
}
@interface Probe : NSObject <NSApplicationDelegate>
@end
@implementation Probe
- (void)event:(NSAppleEventDescriptor *)ev reply:(NSAppleEventDescriptor *)reply {
    AEEventID eid = [ev eventID];
    NSString *kind = eid == kAEOpenApplication ? @"open-application" : eid == kAEReopenApplication ? @"reopen" : eid == kAEPrintDocuments ? @"print" : eid == 'ping' ? @"custom" : @"open";
    NSAppleEventDescriptor *direct = [ev paramDescriptorForKeyword:keyDirectObject];
    NSMutableArray *urls = [NSMutableArray array];
    if (eid == kAEGetURL && direct.stringValue) [urls addObject:direct.stringValue];
    else if (eid == kAEOpenDocuments || eid == kAEPrintDocuments) {
        for (NSInteger i = 1; i <= direct.numberOfItems; i++) {
            NSAppleEventDescriptor *item = [[direct descriptorAtIndex:i] coerceToDescriptorType:typeFileURL];
            NSString *s = [[[NSString alloc] initWithData:item.data encoding:NSUTF8StringEncoding] autorelease];
            if (s) [urls addObject:s];
        }
    }
    record(kind, @{@"urls": urls, @"event_class": @([ev eventClass]), @"event_id": @(eid), @"direct_string": direct.stringValue ?: @""});
}
- (void)applicationWillFinishLaunching:(NSNotification *)note {
    NSAppleEventManager *m = [NSAppleEventManager sharedAppleEventManager];
    for (NSNumber *eid in @[@(kAEOpenApplication), @(kAEReopenApplication), @(kAEOpenDocuments), @(kAEPrintDocuments)]) [m setEventHandler:self andSelector:@selector(event:reply:) forEventClass:kCoreEventClass andEventID:eid.unsignedIntValue];
    [m setEventHandler:self andSelector:@selector(event:reply:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
    [m setEventHandler:self andSelector:@selector(event:reply:) forEventClass:'WPrb' andEventID:'ping'];
}
- (void)applicationDidFinishLaunching:(NSNotification *)note { record(@"finished-launching", nil); }
@end
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    directory = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"WorkspaceProbeReportDirectory"] copy];
    if (![directory isAbsolutePath] || ![[NSFileManager defaultManager] fileExistsAtPath:directory]) return 1;
#if defined(__arm64__)
    NSString *arch = @"arm64";
#elif defined(__i386__)
    NSString *arch = @"i386";
#else
    NSString *arch = @"x86_64";
#endif
    NSMutableArray *args = [NSMutableArray array];
    for (int i = 0; i < argc; i++) [args addObject:[NSString stringWithUTF8String:argv[i]]];
    /* Never enumerate the inherited environment: just the explicitly authorized sentinel. */
    record(@"startup", @{@"argv": args, @"sentinel": [[[NSProcessInfo processInfo] environment] objectForKey:@"WORKSPACE_PROBE_SENTINEL"] ?: (id)[NSNull null], @"architecture": arch});
    NSApplication *app = [NSApplication sharedApplication];
    Probe *delegate = [Probe new];
    app.delegate = delegate;
    [app run];
    [delegate release]; [directory release]; [pool drain];
    return 0;
}
