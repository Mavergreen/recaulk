#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

/* The 10.10/10.12 class methods librecaulk-objc.a's class-method groups provide, declared here as the newer SDKs
   declare them, so this compiles against the 10.9 SDK whatever recipe a profile applies. */
@interface NSTimer (RecaulkClassProvidersTest)
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
@end
@interface NSColor (RecaulkClassProvidersTest)
+ (NSColor *)labelColor;
+ (NSColor *)linkColor;
@end
@interface NSGraphicsContext (RecaulkClassProvidersTest)
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)graphicsPort flipped:(BOOL)initialFlippedState;
@end
#ifdef RECAULK_OWN_LABEL_COLOR
/* A program's own +labelColor: the color group finds a member already there, so it adds neither member. */
@implementation NSColor (RecaulkOwnLabelColor)
+ (NSColor *)labelColor { return [NSColor redColor]; }
@end
#endif

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

static BOOL has(Class c, SEL s) { return class_getClassMethod(c, s) != NULL; }
static void encoding(Class c, SEL sel, const char *want) {
	const char *types = method_getTypeEncoding(class_getClassMethod(c, sel));
	CHECK(types && strcmp(types, want) == 0, "+[%s %s]'s encoding is %s, not %s", class_getName(c), sel_getName(sel),
	      types ? types : "(none)", want);
}
static void spin(NSString *mode, NSTimeInterval seconds) {
	NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
	while ([until timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:mode beforeDate:until];
}

static void timers(void) {
	__block int fired = 0;
	__block NSTimer *seen = nil;
	NSTimer *once = [NSTimer timerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *t) { fired++; seen = t; }];
	CHECK([once isKindOfClass:[NSTimer class]], "timerWithTimeInterval:repeats:block: made a %s", class_getName([once class]));
	CHECK([once isValid], "a new unscheduled timer is not valid");
	spin(NSDefaultRunLoopMode, 0.1);
	CHECK(fired == 0, "timerWithTimeInterval:repeats:block: scheduled its timer (it fired %d times)", fired);
	[[NSRunLoop currentRunLoop] addTimer:once forMode:NSDefaultRunLoopMode];
	spin(NSDefaultRunLoopMode, 0.1);
	CHECK(fired == 1, "a one-shot timer fired %d times, not once", fired);
	CHECK(seen == once, "the block was passed %p, not its timer %p", (void *)seen, (void *)once);
	CHECK(![once isValid], "a one-shot timer is still valid after it fired");

	__block int ticks = 0;
	NSTimer *repeating = [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer *t) {
		if (++ticks == 3) [t invalidate];
	}];
	CHECK(fabs([repeating timeInterval] - 0.01) < 1e-9, "a repeating timer's interval is %g, not 0.01", [repeating timeInterval]);
	/* scheduled in the current run loop's default mode, so another mode never fires it */
	spin(NSModalPanelRunLoopMode, 0.1);
	CHECK(ticks == 0, "a scheduled timer fired %d times in the modal panel mode", ticks);
	spin(NSDefaultRunLoopMode, 0.3);
	CHECK(ticks == 3, "a repeating timer that invalidates itself on its third tick ticked %d times", ticks);
	CHECK(![repeating isValid], "a repeating timer is still valid after it invalidated itself");

	/* platform: NSTimer takes an interval of 0 or less as 0.0001 s (NSTimer.h); so does the provider */
	NSTimer *zero = [NSTimer timerWithTimeInterval:0 repeats:YES block:^(NSTimer *t) { (void)t; }];
	CHECK(fabs([zero timeInterval] - 0.0001) < 1e-9, "a repeating timer of interval 0 has interval %g, not 0.0001", [zero timeInterval]);
	[zero invalidate];
}

static void colors(BOOL own) {
	NSColor *label = [NSColor labelColor];
	if (own) {
		CHECK([label isEqual:[NSColor redColor]], "the program's own +labelColor was replaced");
		CHECK(!has([NSColor class], @selector(linkColor)) && ![NSColor respondsToSelector:@selector(linkColor)],
		      "+linkColor was added although the program has its own +labelColor (a group is added whole or not at all)");
		return;
	}
	CHECK([label isEqual:[NSColor controlTextColor]], "+labelColor is %s, not 10.9's controlTextColor", [[label description] UTF8String]);
	NSColor *link = [[NSColor linkColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	CHECK(link != nil, "+linkColor is nil or has no sRGB form");
	if (link) {
		CHECK(fabs([link redComponent]) < 0.01 && fabs([link greenComponent] - 0.408) < 0.01 &&
		      fabs([link blueComponent] - 0.855) < 0.01 && [link alphaComponent] == 1.0,
		      "+linkColor is %s, not sRGB 0 0.408 0.855 1", [[link description] UTF8String]);
	}
	CHECK([NSColor linkColor] == [NSColor linkColor] || [[NSColor linkColor] isEqual:[NSColor linkColor]], "+linkColor changes between calls");
}

static void graphics(void) {
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef cg = CGBitmapContextCreate(NULL, 4, 4, 8, 16, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(space);
	for (int flipped = 0; flipped < 2; flipped++) {
		NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:(BOOL)flipped];
		CHECK(g != nil, "graphicsContextWithCGContext:flipped:%d returned nil", flipped);
		CHECK([g graphicsPort] == cg, "the context wraps %p, not the CGContext %p", [g graphicsPort], (void *)cg);
		CHECK((BOOL)[g isFlipped] == (BOOL)flipped, "a context made flipped:%d reports isFlipped %d", flipped, (int)[g isFlipped]);
	}
	CGContextRelease(cg);
}

int main(int argc, char **argv) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	const char *how = argc > 1 ? argv[1] : "";
	BOOL rooted = strcmp(how, "rooted") == 0, own = strcmp(how, "own-label-color") == 0;
	Class timer = [NSTimer class], color = [NSColor class];
	Class gc = [NSGraphicsContext class];
	SEL sched = @selector(scheduledTimerWithTimeInterval:repeats:block:), make = @selector(timerWithTimeInterval:repeats:block:);
	SEL label = @selector(labelColor), link = @selector(linkColor), wrap = @selector(graphicsContextWithCGContext:flipped:);
	if (!rooted && !own) {
		/* platform: 10.9 has none of them: the block timers are 10.12, the rest 10.10 */
		CHECK(!has(timer, sched) && !has(timer, make), "an unrooted program's NSTimer has the block methods");
		CHECK(!has(color, label) && !has(color, link), "an unrooted program's NSColor has labelColor or linkColor");
		CHECK(!has(gc, wrap), "an unrooted program's NSGraphicsContext has graphicsContextWithCGContext:flipped:");
	} else if (own) {
		colors(YES);
	} else {
		CHECK(has(timer, sched) && has(timer, make), "a rooted program's NSTimer lacks a block method");
		CHECK(has(color, label) && has(color, link), "a rooted program's NSColor lacks labelColor or linkColor");
		CHECK(has(gc, wrap), "a rooted program's NSGraphicsContext lacks graphicsContextWithCGContext:flipped:");
		if (!failures) {
			encoding([NSTimer class], sched, "@36@0:8d16c24@?28");
			encoding([NSTimer class], make, "@36@0:8d16c24@?28");
			encoding([NSColor class], label, "@16@0:8");
			encoding([NSColor class], link, "@16@0:8");
			encoding([NSGraphicsContext class], wrap, "@28@0:8^{CGContext=}16c24");
			timers();
			colors(NO);
			graphics();
		}
	}
	[pool drain];
	if (failures) return 1;
	printf("objc_class_providers %s: ok\n", rooted ? "rooted" : own ? "own-label-color" : "unrooted");
	return 0;
}
