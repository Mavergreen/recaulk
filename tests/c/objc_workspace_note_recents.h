/* Approved RESEARCH probe: only requested fixture files, after normal launch.
 * No list/property reset, removal, preference change or default-handler lookup.
 * This is NOT a runtime provider or a claim about native failure behavior. */
static BOOL floorNoteRecentFiles(NSArray *urls, NSWorkspaceLaunchOptions flags, NSError **error) {
    if (flags & NSWorkspaceLaunchWithoutAddingToRecents) return YES;
    NSMutableArray *files = [NSMutableArray array];
    for (NSURL *url in urls) if (url.isFileURL) [files addObject:url];
    if (!files.count) return YES;
    LSSharedFileListRef list = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListRecentDocumentItems, NULL);
    BOOL ok = list != NULL;
    CFTypeRef property = list ? LSSharedFileListCopyProperty(list, kLSSharedFileListRecentItemsMaxAmount) : NULL;
    int64_t maximum = -1;
    if (!property || CFGetTypeID(property) != CFNumberGetTypeID() ||
        !CFNumberGetValue((CFNumberRef)property, kCFNumberSInt64Type, &maximum) || maximum < 0) ok = NO;
    if (property) CFRelease(property);
    if (ok && maximum > 0) for (NSURL *file in files) {
        LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(list,
            kLSSharedFileListItemBeforeFirst, NULL, NULL, (CFURLRef)file, NULL, NULL);
        if (!item) { ok = NO; break; }
        CFRelease(item);
    }
    if (list) CFRelease(list);
    if (!ok && error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
        userInfo:@{NSLocalizedDescriptionKey: @"Requested-file Recent Documents bookkeeping could not be completed."}];
    return ok;
}
