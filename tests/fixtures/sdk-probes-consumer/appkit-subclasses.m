// profile: swift-appkit
// spec: .superpowers/specs/2026-11-24-swift-appkit-recipes-design.md -- an Objective-C consumer built with -Werror
//       -Wall against the profile still compiles code written for 10.9's AppKit: subclasses overriding getters the
//       profile converts to properties and the initializers it marks designated, and 10.9's names for the values
//       the profile gathers into NS_OPTIONS/NS_ENUM types
#import <AppKit/AppKit.h>
@interface RCView : NSView @end
@implementation RCView
- (id)initWithFrame:(NSRect)frame { return [super initWithFrame:frame]; }
- (id)initWithCoder:(NSCoder *)coder { return [super initWithCoder:coder]; }
- (BOOL)isHidden { return NO; }
- (NSRect)bounds { return [super bounds]; }
@end
@interface RCWindow : NSWindow @end
@implementation RCWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (NSWindowStyleMask)styleMask { return [super styleMask]; }  // as the 10.12+ SDKs require of an override
@end
@interface RCController : NSViewController @end
@implementation RCController
- (id)initWithNibName:(NSString *)name bundle:(NSBundle *)bundle { return [super initWithNibName:name bundle:bundle]; }
- (id)initWithCoder:(NSCoder *)coder { return [super initWithCoder:coder]; }
@end
@interface RCDelegate : NSObject <NSTextFieldDelegate> @end
@implementation RCDelegate
- (void)controlTextDidChange:(NSNotification *)n { (void)n; }
@end
static NSUInteger rc_uses(NSWindow *w, NSEvent *e, NSView *v, NSTextField *f, NSButton *b) {
  NSWindow *x = [[NSWindow alloc] initWithContentRect:NSZeroRect styleMask:NSTitledWindowMask | NSResizableWindowMask
                                              backing:NSBackingStoreBuffered defer:NO];
  NSTrackingArea *t = [[NSTrackingArea alloc] initWithRect:NSZeroRect
      options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways owner:v userInfo:nil];
  [v setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [f setAlignment:NSCenterTextAlignment];
  [b setState:NSOnState];
  [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];
  NSUInteger flags = [e modifierFlags] & NSCommandKeyMask;
  [x release]; [t release];
  return flags | [w styleMask] | (NSUInteger)[[[NSFontManager sharedFontManager] availableFontFamilies] count];
}
int rc_main(void) { return (int)rc_uses(nil, nil, nil, nil, nil); }
