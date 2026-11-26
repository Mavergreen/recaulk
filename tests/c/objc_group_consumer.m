#import <AppKit/AppKit.h>
#import <recaulk/accessibility.h>

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

/* A class of the consumer's own with only a 10.10 getter, which the accessibility bridge (an own-absent group) is
   called on with a literal class, so Drydock checks the class and credits the bridge's IMPs. */
@interface RecaulkGroupBridged : NSView
- (NSString *)accessibilityRole;
@end
@implementation RecaulkGroupBridged
- (NSString *)accessibilityRole { return NSAccessibilityButtonRole; }
@end

int main(int argc, char **argv) {
	(void)argv;
	recaulk_accessibility_bridge([RecaulkGroupBridged class]);
	if (argc > 5) {
		[NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *t) { (void)t; }];
		[NSTimer timerWithTimeInterval:1 repeats:NO block:^(NSTimer *t) { (void)t; }];
		[NSColor labelColor];
		[NSColor linkColor];
		[NSGraphicsContext graphicsContextWithCGContext:NULL flipped:NO];
		/* receivers from sends the 10.9 SDK types with the class (Drydock's floor-signatures.tsv): alloc,
		   -[NSWindow contentView] and -[NSControl cell] return id there, which leaves every send after it unresolved */
		NSView *view = [[NSMenuItem separatorItem] view];
		NSCell *cell = [[[NSApplication sharedApplication] mainWindow] defaultButtonCell];
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
