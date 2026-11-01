/* Characterize actual research helper with recording CF boundary ONLY.
 * No shared-list API is executed and no global preference is changed. */
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
static NSMutableArray *recorded;
static int opens, inserts, failAt, failOpen, missing;
static int64_t maximum;
static LSSharedFileListRef testCreate(CFAllocatorRef a, CFStringRef kind, CFTypeRef options) {
    opens++;
    return failOpen ? NULL : (LSSharedFileListRef)CFRetain(CFSTR("recording-list"));
}
static CFTypeRef testProperty(LSSharedFileListRef list, CFStringRef name) {
    return missing ? NULL : CFNumberCreate(NULL, kCFNumberSInt64Type, &maximum);
}
static LSSharedFileListItemRef testInsert(LSSharedFileListRef list, LSSharedFileListItemRef after,
    CFStringRef name, IconRef icon, CFURLRef url, CFDictionaryRef properties, CFArrayRef clear) {
    if (inserts++ == failAt) return NULL;
    [recorded addObject:(NSURL *)url];
    return (LSSharedFileListItemRef)CFRetain(CFSTR("recorded-item"));
}
#define LSSharedFileListCreate testCreate
#define LSSharedFileListCopyProperty testProperty
#define LSSharedFileListInsertItemURL testInsert
#ifndef FLOOR_NOTE_HEADER
#define FLOOR_NOTE_HEADER "objc_workspace_note_recents.h"
#endif
#include FLOOR_NOTE_HEADER
static void reset(void) { recorded=[NSMutableArray array]; opens=inserts=failOpen=missing=0; maximum=10; failAt=-1; }
#define CHECK(x, message) do { if (!(x)) { printf("FAIL line%d: %s\n", __LINE__, message); failures++; } } while (0)
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new]; int failures=0;
    NSURL *one=[NSURL fileURLWithPath:@"/private/owned-one.txt"], *two=[NSURL fileURLWithPath:@"/private/owned-two.txt"];
    NSArray *files=@[one,two]; NSError *e=nil;
    reset(); maximum=0;
    CHECK(floorNoteRecentFiles(files, 0, &e) && !e && !recorded.count, "disabled system Recents makes no insertion");
    reset();
    CHECK(floorNoteRecentFiles(files, NSWorkspaceLaunchWithoutAddingToRecents, &e) && !opens && !recorded.count, "WithoutAddingToRecents does not even open the list");
    reset();
    CHECK(floorNoteRecentFiles(@[[NSURL URLWithString:@"https://example.invalid/"]], 0, &e) && !opens, "browser-only request does not open document history");
    reset();
    CHECK(floorNoteRecentFiles(files, 0, &e) && [recorded isEqual:files], "only requested files recorded, in supplied order");
    reset(); missing=1; e=nil;
    CHECK(!floorNoteRecentFiles(files, 0, &e) && e && !recorded.count, "unknown preference refuses a guessed history write");
    reset(); maximum=-1; e=nil;
    CHECK(!floorNoteRecentFiles(files, 0, &e) && e && !recorded.count, "unsupported preference value refuses writes");
    reset(); failOpen=1; e=nil;
    CHECK(!floorNoteRecentFiles(files, 0, &e) && e && !recorded.count, "unavailable list is explicit failure");
    reset(); failAt=1; e=nil;
    CHECK(!floorNoteRecentFiles(files, 0, &e) && e && [recorded isEqual:@[one]], "partial insertion fails without rollback or unrelated removal");
    reset(); e=[NSError errorWithDomain:@"sentinel" code:9 userInfo:nil]; NSError *sentinel=e;
    CHECK(floorNoteRecentFiles(@[], 0, &e) && e==sentinel && !opens, "empty success preserves caller error pointer");
    printf("%s: research Recents decision logic, disabled preference and failure boundaries (recording APIs; no shared-history edits)\n", failures ? "FAIL" : "PASS");
    [pool drain]; return failures ? 1 : 0;
}
