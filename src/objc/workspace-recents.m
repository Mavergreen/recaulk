/* Supplemental document bookkeeping after successful launch/queue operations.
 * Only public APIs; never remove/reset history or change a preference. */
#import "workspace-private.h"
BOOL __recaulk_workspace_note_recent_files(NSArray *urls, NSWorkspaceLaunchOptions options, NSError **error) {
    if (options & NSWorkspaceLaunchWithoutAddingToRecents) return YES;
    NSMutableArray *documents=[NSMutableArray array];
    for (id value in urls) if ([value isKindOfClass:[NSURL class]] && [value isFileURL]) [documents addObject:value];
    if (!documents.count) return YES;
    BOOL completed=NO;
    LSSharedFileListRef recent=LSSharedFileListCreate(kCFAllocatorDefault,kLSSharedFileListRecentDocumentItems,NULL);
    if (recent) {
        CFTypeRef setting=LSSharedFileListCopyProperty(recent,kLSSharedFileListRecentItemsMaxAmount);
        int64_t limit=-1;
        BOOL known=setting && CFGetTypeID(setting)==CFNumberGetTypeID() && CFNumberGetValue((CFNumberRef)setting,kCFNumberSInt64Type,&limit) && limit>=0;
        if (setting) CFRelease(setting);
        if (known) {
            completed=YES;
            if (limit>0) for (NSURL *document in documents) {
                LSSharedFileListItemRef item=LSSharedFileListInsertItemURL(recent,kLSSharedFileListItemBeforeFirst,NULL,NULL,(CFURLRef)document,NULL,NULL);
                if (!item) { completed=NO; break; }
                CFRelease(item);
            }
        }
        CFRelease(recent);
    }
    if (!completed && error) *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
        userInfo:@{NSLocalizedDescriptionKey:@"Unable to complete requested-file Recent Documents bookkeeping; launch or earlier operations may have occurred."}];
    return completed;
}
