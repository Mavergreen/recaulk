#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

/* Declared here: a program built against the 10.9 SDK sees these through Recaulk's SDK metadata. */
@interface NSLocale (RecaulkProviderTest)
- (NSString *)languageCode;
- (NSString *)countryCode;
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

static int same(NSString *a, NSString *b) { return a == b || [a isEqual:b]; }

static void codes(NSString *identifier, NSString *language, NSString *country) {
	NSLocale *l = [[[NSLocale alloc] initWithLocaleIdentifier:identifier] autorelease];
	CHECK(same([l languageCode], language), "%s languageCode is %s, want %s", [identifier UTF8String],
	      [[l languageCode] UTF8String] ?: "nil", [language UTF8String] ?: "nil");
	CHECK(same([l countryCode], country), "%s countryCode is %s, want %s", [identifier UTF8String],
	      [[l countryCode] UTF8String] ?: "nil", [country UTF8String] ?: "nil");
	CHECK(same([l languageCode], [l objectForKey:NSLocaleLanguageCode]), "%s languageCode disagrees with objectForKey:", [identifier UTF8String]);
	CHECK(same([l countryCode], [l objectForKey:NSLocaleCountryCode]), "%s countryCode disagrees with objectForKey:", [identifier UTF8String]);
}

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	int rooted = argc > 1 && strcmp(argv[1], "rooted") == 0;
	BOOL responds = [NSLocale instancesRespondToSelector:@selector(languageCode)]
	             && [NSLocale instancesRespondToSelector:@selector(countryCode)];
	if (!rooted) {
		/* platform: 10.9's NSLocale has neither method, so an unrooted program must not gain them. */
		CHECK(!responds, "the providers activated without their root");
	} else {
		CHECK(responds, "the rooted providers did not activate");
		if (responds) {
			codes(@"en_US", @"en", @"US");
			codes(@"fr_CA", @"fr", @"CA");
			codes(@"fr", @"fr", nil);
			CHECK([[[[NSLocale alloc] initWithLocaleIdentifier:@""] autorelease] countryCode] == nil,
			      "the empty locale has a countryCode");
			/* platform: 10.9's objectForKey: has no language for these, but Apple declares languageCode
			   nonnull, and a binding that trusts that (objc2's) treats nil as a fault: "" is the answer. */
			for (NSString *identifier in [NSArray arrayWithObjects:@"", @"_US", nil]) {
				NSString *language = [[[[NSLocale alloc] initWithLocaleIdentifier:identifier] autorelease] languageCode];
				CHECK([language isEqual:@""], "'%s' languageCode is %s, want the empty string",
				      [identifier UTF8String], language ? [language UTF8String] : "nil");
			}
		}
	}
	[pool drain];
	if (failures) return 1;
	printf("objc_foundation_providers %s: ok\n", rooted ? "rooted" : "unrooted");
	return 0;
}
