/* Research-only, read-only fixture matching. Never resolve an unrelated URL. */
static NSInteger floorRecentURLMatch(NSURL *candidate, NSArray *knownPrivateURLs) {
    NSString *key = candidate.absoluteString;
    for (NSURL *known in knownPrivateURLs) {
        /* All filesystem work is on already validated PRIVATE inputs. Comparing
         * NSURL objects of mixed reference/path form could resolve an unrelated
         * candidate; compare literal strings instead. */
        if ([key isEqual:known.absoluteString]) return 1;
        NSURL *reference = known.fileReferenceURL;
        if (reference) {
            NSString *ref = reference.absoluteString;
            if ([key isEqual:ref]) return 1;
            if (candidate.isFileReferenceURL &&
                [[key stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]
                 isEqual:[ref stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]]) return 1;
        }
    }
    return candidate.isFileReferenceURL ? -1 : 0;
}
static NSDictionary *floorRecentList(CFStringRef kind, NSURL *app, NSArray *files) {
    LSSharedFileListRef list = LSSharedFileListCreate(kCFAllocatorDefault, kind, NULL);
    if (!list) return @{ @"available": @NO };
    UInt32 seed = 0;
    CFArrayRef snapshot = LSSharedFileListCopySnapshot(list, &seed);
    CFIndex total = snapshot ? CFArrayGetCount(snapshot) : 0;
    NSMutableArray *known = [NSMutableArray arrayWithObjects:app, [app URLByResolvingSymlinksInPath], nil];
    for (NSURL *file in files) { [known addObject:file]; [known addObject:[file URLByResolvingSymlinksInPath]]; }
    NSUInteger matches = 0, unresolved = 0;
    if (snapshot) for (CFIndex i = 0; i < CFArrayGetCount(snapshot); i++) {
        CFURLRef url = NULL;
        OSStatus status = LSSharedFileListItemResolve((LSSharedFileListItemRef)CFArrayGetValueAtIndex(snapshot, i),
            kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes, &url, NULL);
        if (status || !url) unresolved++;
        else {
            NSInteger match = floorRecentURLMatch((NSURL *)url, known);
            if (match == 1) matches++; else if (match == -1) unresolved++;
        }
        if (url) CFRelease(url);
    }
    BOOL available = snapshot != NULL;
    if (snapshot) CFRelease(snapshot);
    CFTypeRef maximum = LSSharedFileListCopyProperty(list, kLSSharedFileListRecentItemsMaxAmount);
    id limit = maximum && CFGetTypeID(maximum) == CFNumberGetTypeID() ? [[(NSNumber *)maximum copy] autorelease] : (id)[NSNull null];
    if (maximum) CFRelease(maximum);
    CFRelease(list);
    return @{ @"available": @(available), @"matching_private_items": @(matches), @"unresolved_item_count": @(unresolved), @"items_limit": limit, @"snapshot_seed": @(seed), @"item_count": @(total) };
}
static NSDictionary *floorRecents(NSURL *app, NSArray *files) {
    return @{ @"applications": floorRecentList(kLSSharedFileListRecentApplicationItems, app, files),
              @"documents": floorRecentList(kLSSharedFileListRecentDocumentItems, app, files) };
}
