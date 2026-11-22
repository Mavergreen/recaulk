/*
 * LSCopyApplicationURLsForBundleIdentifier (CoreServices, 10.10+) -- custom polyfill.
 *
 * 10.9's LaunchServices finds one application for a bundle identifier, the one it would launch
 * (LSFindApplicationForInfo), not every copy: so the array holds that one URL. On failure: NULL, and
 * *outError (when given) an OSStatus-domain CFError, as 10.10's does.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>

CFArrayRef LSCopyApplicationURLsForBundleIdentifier(CFStringRef inBundleIdentifier, CFErrorRef *outError) {
	CFURLRef appURL = NULL;
	OSStatus st = inBundleIdentifier
		? LSFindApplicationForInfo(kLSUnknownCreator, inBundleIdentifier, NULL, NULL, &appURL)
		: paramErr;
	if (st != noErr || !appURL) {
		if (appURL) CFRelease(appURL);
		if (outError) *outError = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainOSStatus,
		                                        st != noErr ? st : kLSApplicationNotFoundErr, NULL);
		return NULL;
	}
	CFArrayRef urls = CFArrayCreate(kCFAllocatorDefault, (const void **)&appURL, 1, &kCFTypeArrayCallBacks);
	CFRelease(appURL);
	return urls;
}
