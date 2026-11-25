#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/* One libFixture.dylib per case of tests/objc-accessibility-standin.sh, loaded by the app beside Recaulk's shim:
     FAKE:     an NSAccessibilityElement, as 10.10's AppKit has, for the re-parent to find on 10.9. The shim is still
               unrealized when its constructor runs, as on 10.10 and later: objc4-551's class_setSuperclass dereferences
               NULL on an unrealized class, so this case proves the constructor realizes it first;
     EARLY:    that fake and a +load that realizes the shim before its constructor runs: the re-parent still takes;
     LARGER:   the fake with an ivar, larger than the shim: the constructor refuses the re-parent before trying it;
     CXX:      the fake with a .cxx_destruct, as an ARC or C++ ivar gives a class, at the shim's instance size (added at
               +load, since any ivar that gives one would also make the fake larger): refused too;
     CONFLICT: a category on the shim with its own accessibilityRole, so the stand-in's cannot land. */

#if defined(FAKE) || defined(EARLY) || defined(LARGER) || defined(CXX)
@interface NSAccessibilityElement : NSObject
#if defined(LARGER)
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

#if defined(CXX)
static void cxx_destruct(id self, SEL _cmd) { (void)self; (void)_cmd; }
@interface CxxIvars : NSObject
@end
@implementation CxxIvars
+ (void)load {
    class_addMethod(objc_getClass("NSAccessibilityElement"), sel_registerName(".cxx_destruct"), (IMP)cxx_destruct, "v16@0:8");
}
@end
#endif

#if defined(EARLY)
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
