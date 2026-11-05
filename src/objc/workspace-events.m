/* Standard event planning only: no app selection, launch or sends. */
#import "workspace-private.h"
static NSAppleEventDescriptor *event(AEEventClass cls, AEEventID identifier, NSAppleEventDescriptor *value) {
    NSAppleEventDescriptor *e=[NSAppleEventDescriptor appleEventWithEventClass:cls eventID:identifier
        targetDescriptor:nil returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    if (e && value) [e setParamDescriptor:value forKeyword:keyDirectObject];
    return e;
}
NSArray *__recaulk_workspace_url_events(NSArray *urls, NSWorkspaceLaunchOptions options, NSError **error) {
    NSMutableArray *files=[NSMutableArray array], *others=[NSMutableArray array], *result=[NSMutableArray array];
    for (id value in urls) if ([value isKindOfClass:[NSURL class]]) {
        if ([value isFileURL]) [files addObject:value]; else [others addObject:value];
    }
    BOOL ok=YES;
    if (files.count) {
        NSAppleEventDescriptor *list=[NSAppleEventDescriptor listDescriptor];
        for (NSURL *url in files) {
            NSData *bytes=[url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
            NSAppleEventDescriptor *item=bytes ? [NSAppleEventDescriptor descriptorWithDescriptorType:typeFileURL data:bytes] : nil;
            if (!item) { ok=NO; break; }
            [list insertDescriptor:item atIndex:list.numberOfItems+1];
        }
        NSAppleEventDescriptor *e=ok ? event(kCoreEventClass, (options & NSWorkspaceLaunchAndPrint) ? kAEPrintDocuments : kAEOpenDocuments, list) : nil;
        if (e) [result addObject:e]; else ok=NO;
    }
    for (NSURL *url in others) {
        NSString *string=url.absoluteString;
        NSAppleEventDescriptor *value=string ? [NSAppleEventDescriptor descriptorWithString:string] : nil;
        NSAppleEventDescriptor *e=value ? event(kInternetEventClass,kAEGetURL,value) : nil;
        if (!e) { ok=NO; break; }
        [result addObject:e];
    }
    if (ok) return result;
    if (error) *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError
        userInfo:@{NSLocalizedDescriptionKey:@"Unable to construct a requested URL Apple event."}];
    return nil;
}
