#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

int main(void) {
	CFErrorRef error = NULL;
	CFArrayRef urls = LSCopyApplicationURLsForBundleIdentifier(CFSTR("com.apple.finder"), &error);
	CHECK(urls && CFArrayGetCount(urls) >= 1, "no URL for com.apple.finder");
	CHECK(!error, "an error with a result");
	if (urls && CFArrayGetCount(urls) >= 1) {
		CFURLRef u = CFArrayGetValueAtIndex(urls, 0);
		CFStringRef name = CFURLCopyLastPathComponent(u);
		CHECK(name && CFEqual(name, CFSTR("Finder.app")), "com.apple.finder's first URL is not Finder.app");
		if (name) CFRelease(name);
	}
	if (urls) CFRelease(urls);

	error = NULL;
	urls = LSCopyApplicationURLsForBundleIdentifier(CFSTR("dev.mavergreen.recaulk.no-such-app"), &error);
	CHECK(!urls, "a URL for an application that does not exist");
	CHECK(error && CFEqual(CFErrorGetDomain(error), kCFErrorDomainOSStatus) && CFErrorGetCode(error) == kLSApplicationNotFoundErr,
	      "no kLSApplicationNotFoundErr error for an application that does not exist");
	if (error) CFRelease(error);
	CHECK(!LSCopyApplicationURLsForBundleIdentifier(CFSTR("dev.mavergreen.recaulk.no-such-app"), NULL), "a URL with no error out");
	if (failures) return 1;
	printf("launchservices_bundle_urls: ok\n");
	return 0;
}
