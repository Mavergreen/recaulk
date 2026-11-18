#import <Foundation/Foundation.h>
#include <stdio.h>

/* What foundation-processinfo-version-v1 declares, and relies on 10.9.5's Foundation to implement. */
typedef struct { NSInteger majorVersion; NSInteger minorVersion; NSInteger patchVersion; } RecaulkTestVersion;
@interface NSProcessInfo (RecaulkTest)
- (RecaulkTestVersion)operatingSystemVersion;
- (BOOL)isOperatingSystemAtLeastVersion:(RecaulkTestVersion)version;
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

int main(void) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSProcessInfo *p = [NSProcessInfo processInfo];
	CHECK([p respondsToSelector:@selector(operatingSystemVersion)], "Foundation has no operatingSystemVersion");
	CHECK([p respondsToSelector:@selector(isOperatingSystemAtLeastVersion:)], "Foundation has no isOperatingSystemAtLeastVersion:");
	if (failures) return 1;
	RecaulkTestVersion v = [p operatingSystemVersion];
	NSString *product = [[NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"]
	                     objectForKey:@"ProductVersion"];
	NSArray *parts = [product componentsSeparatedByString:@"."];
	NSInteger want[3] = {0, 0, 0};
	for (NSUInteger i = 0; i < 3 && i < [parts count]; i++) want[i] = [[parts objectAtIndex:i] integerValue];
	CHECK(product && v.majorVersion == want[0] && v.minorVersion == want[1] && v.patchVersion == want[2],
	      "operatingSystemVersion is %ld.%ld.%ld, SystemVersion.plist says %s", (long)v.majorVersion,
	      (long)v.minorVersion, (long)v.patchVersion, [product UTF8String] ?: "nothing");
	RecaulkTestVersion floor = {10, 9, 5}, above = {v.majorVersion, v.minorVersion, v.patchVersion + 1};
	CHECK([p isOperatingSystemAtLeastVersion:floor], "this Mac is not at least 10.9.5");
	CHECK([p isOperatingSystemAtLeastVersion:v], "this Mac is not at least its own version");
	CHECK(![p isOperatingSystemAtLeastVersion:above], "this Mac is at least a version above its own");
	[pool drain];
	if (failures) return 1;
	printf("foundation_os_version: %ld.%ld.%ld ok\n", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion);
	return 0;
}
