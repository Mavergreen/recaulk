#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

/* The provider's reading, by preference domain, so a throwaway domain can stand in for universal access. */
BOOL __recaulk_objc_voiceover_enabled_in(CFStringRef domain);

@interface NSWorkspace (RecaulkVoiceOverTest)
- (BOOL)isVoiceOverEnabled;
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

static void set_test_value(CFStringRef domain, CFPropertyListRef value) {
	CFPreferencesSetAppValue(CFSTR("voiceOverOnOffKey"), value, domain);
	CFPreferencesAppSynchronize(domain);
}

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL rooted = argc > 1 && strcmp(argv[1], "rooted") == 0;
	BOOL responds = [[NSWorkspace sharedWorkspace] respondsToSelector:@selector(isVoiceOverEnabled)];
	if (!rooted) {
		/* platform: 10.9's NSWorkspace has no isVoiceOverEnabled (10.13) */
		CHECK(!responds, "an unrooted program's NSWorkspace has isVoiceOverEnabled");
	} else {
		CHECK(responds, "a rooted program's NSWorkspace has no isVoiceOverEnabled");
		if (responds) {
			/* platform: VoiceOver records its state in universal access's voiceOverOnOffKey; measured on 10.9.5,
			   it is set as VoiceOver starts and cleared as it stops, and not while its welcome dialog is up. */
			CFPreferencesAppSynchronize(CFSTR("com.apple.universalaccess"));
			BOOL want = CFPreferencesGetAppBooleanValue(CFSTR("voiceOverOnOffKey"), CFSTR("com.apple.universalaccess"), NULL);
			CHECK([[NSWorkspace sharedWorkspace] isVoiceOverEnabled] == want, "isVoiceOverEnabled is not universal access's voiceOverOnOffKey (%d)", want);
		}
		CFStringRef domain = CFSTR("dev.mavergreen.recaulk.test-voiceover");
		set_test_value(domain, NULL);
		CHECK(!__recaulk_objc_voiceover_enabled_in(domain), "no recorded state reads as on");
		set_test_value(domain, kCFBooleanTrue);
		CHECK(__recaulk_objc_voiceover_enabled_in(domain), "a recorded true reads as off");
		set_test_value(domain, kCFBooleanFalse);
		CHECK(!__recaulk_objc_voiceover_enabled_in(domain), "a recorded false reads as on");
		int one = 1;
		CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &one);
		set_test_value(domain, n);
		CFRelease(n);
		CHECK(__recaulk_objc_voiceover_enabled_in(domain), "a recorded 1, as defaults writes it, reads as off");
		set_test_value(domain, NULL);
	}
	[pool drain];
	if (failures) return 1;
	printf("objc_workspace_voiceover %s: ok\n", rooted ? "rooted" : "unrooted");
	return 0;
}
