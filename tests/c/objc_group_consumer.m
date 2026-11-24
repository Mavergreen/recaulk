#import <AppKit/AppKit.h>

/* A consumer of the class-method groups, for tests/objc-provider-groups.sh: one send of each member, which 10.9 lacks,
   so Drydock's strict analyzer calls each one unsupported unless it credits the group that provides it. */
@interface NSTimer (RecaulkGroupConsumer)
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
@end
@interface NSColor (RecaulkGroupConsumer)
+ (NSColor *)labelColor;
+ (NSColor *)linkColor;
@end
@interface NSGraphicsContext (RecaulkGroupConsumer)
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)graphicsPort flipped:(BOOL)initialFlippedState;
@end

int main(int argc, char **argv) {
	(void)argv;
	if (argc > 5) {
		[NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *t) { (void)t; }];
		[NSTimer timerWithTimeInterval:1 repeats:NO block:^(NSTimer *t) { (void)t; }];
		[NSColor labelColor];
		[NSColor linkColor];
		[NSGraphicsContext graphicsContextWithCGContext:NULL flipped:NO];
	}
	return 0;
}
