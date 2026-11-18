#import <Foundation/Foundation.h>
#include <stdio.h>

/* A program's own implementation is attached when the image maps, before Recaulk's root runs. */
@implementation NSLocale (RecaulkOwnMethod)
- (NSString *)languageCode { return @"zz"; }
@end

/* An inherited one too: Recaulk walks the superclasses, so NSObject's countryCode is not shadowed on NSLocale. */
@implementation NSObject (RecaulkOwnInheritedMethod)
- (NSString *)countryCode { return @"ZZ"; }
@end

int main(void) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSLocale *l = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease];
	NSString *got = [l languageCode];
	int ok = [got isEqual:@"zz"];
	if (!ok) printf("FAIL: the program's own languageCode was replaced: it returned %s\n", [got UTF8String]);
	NSString *country = [l countryCode];
	if (![country isEqual:@"ZZ"]) {
		printf("FAIL: NSObject's own countryCode was shadowed on NSLocale: it returned %s\n", [country UTF8String]);
		ok = 0;
	}
	if ([NSLocale instanceMethodForSelector:@selector(countryCode)] != [NSObject instanceMethodForSelector:@selector(countryCode)]) {
		printf("FAIL: NSLocale has a countryCode of its own, not NSObject's\n");
		ok = 0;
	}
	if (ok) printf("objc_foundation_own_method: ok\n");
	[pool drain];
	return ok ? 0 : 1;
}
