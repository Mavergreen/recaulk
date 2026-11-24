#import <AppKit/AppKit.h>

/* A consumer of the groups, for tests/objc-provider-groups.sh: one send of each member, which 10.9 lacks,
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
@interface NSView (RecaulkGroupConsumer)
- (void)setAccessibilityLabel:(NSString *)label;
- (NSString *)accessibilityLabel;
- (void)setAccessibilityRole:(NSString *)role;
- (NSString *)accessibilityRole;
- (void)setAccessibilityChildren:(NSArray *)children;
- (NSArray *)accessibilityChildren;
- (void)setAccessibilitySelectedTextRange:(NSRange)range;
- (NSRange)accessibilitySelectedTextRange;
- (NSRect)accessibilityFrame;
@end
@interface NSCell (RecaulkGroupConsumer)
- (void)setAccessibilityLabel:(NSString *)label;
- (NSString *)accessibilityLabel;
- (void)setAccessibilityRole:(NSString *)role;
- (NSString *)accessibilityRole;
- (void)setAccessibilityChildren:(NSArray *)children;
- (NSArray *)accessibilityChildren;
- (void)setAccessibilitySelectedTextRange:(NSRange)range;
- (NSRange)accessibilitySelectedTextRange;
- (NSRect)accessibilityFrame;
@end

int main(int argc, char **argv) {
	(void)argv;
	if (argc > 5) {
		[NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *t) { (void)t; }];
		[NSTimer timerWithTimeInterval:1 repeats:NO block:^(NSTimer *t) { (void)t; }];
		[NSColor labelColor];
		[NSColor linkColor];
		[NSGraphicsContext graphicsContextWithCGContext:NULL flipped:NO];
		/* receivers from sends whose declared return type names the class: alloc returns id, which leaves
		   every send after it unresolved */
		NSView *view = [[[NSApplication sharedApplication] mainWindow] contentView];
		NSCell *cell = [[NSWindow standardWindowButton:NSWindowCloseButton forStyleMask:NSTitledWindowMask] cell];
		[view setAccessibilityLabel:@"x"];
		(void)[view accessibilityLabel];
		[view setAccessibilityRole:@"x"];
		(void)[view accessibilityRole];
		[view setAccessibilityChildren:nil];
		(void)[view accessibilityChildren];
		[view setAccessibilitySelectedTextRange:NSMakeRange(0, 0)];
		(void)[view accessibilitySelectedTextRange];
		(void)[view accessibilityFrame];
		[cell setAccessibilityLabel:@"x"];
		(void)[cell accessibilityLabel];
		[cell setAccessibilityRole:@"x"];
		(void)[cell accessibilityRole];
		[cell setAccessibilityChildren:nil];
		(void)[cell accessibilityChildren];
		[cell setAccessibilitySelectedTextRange:NSMakeRange(0, 0)];
		(void)[cell accessibilitySelectedTextRange];
		(void)[cell accessibilityFrame];
	}
	return 0;
}
