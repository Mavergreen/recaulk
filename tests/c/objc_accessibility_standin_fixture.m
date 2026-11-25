#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/* One libFixture.dylib per case of tests/objc-accessibility-standin.sh, loaded by the app beside Recaulk's shim:
     FAKE:     an NSAccessibilityElement, as 10.10's AppKit has, for the re-parent to find on 10.9, and a +load that
               realizes the shim before its constructor runs: objc4-551's class_setSuperclass dereferences NULL on an
               unrealized class, so only a realized shim re-parents on 10.9 (the same NSObject instance size as the
               fake, so the constructor's checks pass);
     EARLY:    that fake with an ivar, so the early-realized shim is smaller than its target: the hazard the shim's
               constructor detects by instance size;
     CONFLICT: a category on the shim with its own accessibilityRole, so the stand-in's cannot land. */

#if defined(FAKE) || defined(EARLY)
@interface NSAccessibilityElement : NSObject
#if defined(EARLY)
{
    id unused;
}
#endif
@end
@implementation NSAccessibilityElement
- (NSString *)accessibilityRole { return @"from the fake"; }
- (NSString *)accessibilityLabel { return @"from the fake"; }
@end
#endif

#if defined(FAKE) || defined(EARLY)
@interface EarlyUse : NSObject
@end
@implementation EarlyUse
/* spec: Drydock's provided-class design, "The hazard" -- a +load before the shim's constructor realizes it */
+ (void)load { [objc_getClass("RecaulkAccessibilityElement") class]; }
@end
#endif

#if defined(CONFLICT)
@interface RecaulkAccessibilityElement : NSObject
@end
@implementation RecaulkAccessibilityElement (Conflict)
- (NSString *)accessibilityRole { return @"from the category"; }
@end
#endif
