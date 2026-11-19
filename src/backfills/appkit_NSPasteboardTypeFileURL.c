#include <CoreFoundation/CoreFoundation.h>

/* AppKit constant (added 10.13): the file-URL UTI, the string kUTTypeFileURL names on 10.9. A constant
   CFString needs CoreFoundation only. Not AppKit's pointer on 10.13+, so compare it with isEqual:. */
const CFStringRef NSPasteboardTypeFileURL = CFSTR("public.file-url");
