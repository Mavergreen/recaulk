#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

/* What a newer SDK's clang emits for @{} and @[]: the address of CoreFoundation's shared empty collection. */
extern char __NSDictionary0__struct[];
extern char __NSArray0__struct[];

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

static void dictionary(void) {
	NSDictionary *d = (NSDictionary *)(void *)__NSDictionary0__struct;
	NSDictionary *empty = [NSDictionary dictionary];
	CHECK([d isKindOfClass:[NSDictionary class]], "the empty dictionary is a %s, not an NSDictionary", object_getClassName(d));
	CHECK(![d isKindOfClass:[NSMutableDictionary class]] || [d class] == [empty class], "the empty dictionary is mutable");
	CHECK([d count] == 0, "the empty dictionary counts %lu", (unsigned long)[d count]);
	CHECK(CFDictionaryGetCount((CFDictionaryRef)d) == 0, "CoreFoundation counts the empty dictionary as non-empty");
	CHECK([d objectForKey:@"k"] == nil, "the empty dictionary holds k");
	CHECK([d isEqual:empty] && [empty isEqual:d], "the empty dictionary is not equal to [NSDictionary dictionary]");
	CHECK([d hash] == [empty hash], "the empty dictionary hashes differently from [NSDictionary dictionary]");
	CHECK([[d allKeys] count] == 0, "the empty dictionary has keys");
	NSUInteger n = 0;
	for (id k in d) { (void)k; n++; }
	CHECK(n == 0, "the empty dictionary enumerates %lu keys", (unsigned long)n);
	for (int i = 0; i < 10000; i++) [[d retain] autorelease];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	for (int i = 0; i < 10000; i++) { [d retain]; [d release]; [[d retain] autorelease]; }
	[pool drain];
	CHECK([d count] == 0, "the empty dictionary did not survive balanced retains and releases");
	NSDictionary *c = [d copy];
	CHECK([c count] == 0, "a copy of the empty dictionary is not empty");
	[c release];
	NSMutableDictionary *m = [d mutableCopy];
	[m setObject:@"v" forKey:@"k"];
	CHECK([m count] == 1 && [d count] == 0, "a mutable copy of the empty dictionary is not independent of it");
	[m release];
	CHECK([[d description] isEqual:[empty description]], "the empty dictionary describes itself as %s", [[d description] UTF8String]);
}

static void array(void) {
	NSArray *a = (NSArray *)(void *)__NSArray0__struct;
	NSArray *empty = [NSArray array];
	CHECK([a isKindOfClass:[NSArray class]], "the empty array is a %s, not an NSArray", object_getClassName(a));
	CHECK(![a isKindOfClass:[NSMutableArray class]] || [a class] == [empty class], "the empty array is mutable");
	CHECK([a count] == 0, "the empty array counts %lu", (unsigned long)[a count]);
	CHECK(CFArrayGetCount((CFArrayRef)a) == 0, "CoreFoundation counts the empty array as non-empty");
	CHECK([a lastObject] == nil, "the empty array has a last object");
	CHECK([a isEqual:empty] && [empty isEqual:a], "the empty array is not equal to [NSArray array]");
	CHECK([a hash] == [empty hash], "the empty array hashes differently from [NSArray array]");
	NSUInteger n = 0;
	for (id o in a) { (void)o; n++; }
	CHECK(n == 0, "the empty array enumerates %lu objects", (unsigned long)n);
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	for (int i = 0; i < 10000; i++) { [a retain]; [a release]; [[a retain] autorelease]; }
	[pool drain];
	CHECK([a count] == 0, "the empty array did not survive balanced retains and releases");
	NSMutableArray *m = [a mutableCopy];
	[m addObject:@"x"];
	CHECK([m count] == 1 && [a count] == 0, "a mutable copy of the empty array is not independent of it");
	[m release];
	CHECK([[a arrayByAddingObject:@"x"] count] == 1, "the empty array cannot make a one-object array");
	CHECK([[a description] isEqual:[empty description]], "the empty array describes itself as %s", [[a description] UTF8String]);
}

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	if (argc < 2 || !strcmp(argv[1], "dictionary")) dictionary();
	if (argc < 2 || !strcmp(argv[1], "array")) array();
	[pool drain];
	return failures ? 1 : 0;
}
