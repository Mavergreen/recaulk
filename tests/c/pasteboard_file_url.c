#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <stdio.h>

/* AppKit's declaration is Objective-C; a C caller names the same object as a CFStringRef. */
extern const CFStringRef NSPasteboardTypeFileURL;

int main(void) {
	int failures = 0;
	if (!NSPasteboardTypeFileURL) { printf("FAIL: NSPasteboardTypeFileURL is NULL\n"); return 1; }
	if (!CFEqual(NSPasteboardTypeFileURL, CFSTR("public.file-url"))) { printf("FAIL: NSPasteboardTypeFileURL is not \"public.file-url\"\n"); failures++; }
	/* An oracle 10.9 has: the UTI kUTTypeFileURL names, which AppKit's constant equals on 10.13+. */
	if (!CFEqual(NSPasteboardTypeFileURL, kUTTypeFileURL)) { printf("FAIL: NSPasteboardTypeFileURL is not kUTTypeFileURL\n"); failures++; }
	if (failures) return 1;
	printf("pasteboard_file_url: ok\n");
	return 0;
}
