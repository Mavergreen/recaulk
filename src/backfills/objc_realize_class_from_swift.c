/*
 * _objc_realizeClassFromSwift for OS X 10.9 -- apart from objc_readClassPair,
 * so that its call to objc_readClassPair crosses objects.
 *
 * A consumer must ask for this symbol deliberately, because merely defining it
 * changes behaviour elsewhere. The ModernMavericks Swift runtime checks at run
 * time whether objc_readClassPair exists and, when it does, hands class
 * realization to it -- bypassing the realization it does itself, which is the
 * path that project validated on real 10.9. Linking this in by accident, as a
 * side effect of pulling some neighbouring objc helper out of the same object
 * file, silently swaps a tested code path for this one.
 *
 * So: link it only where nothing else provides class realization.
 *
 */

#include <stdlib.h>
#include <objc/runtime.h>

Class objc_readClassPair(Class cls, const void *info);

/*
 * _objc_realizeClassFromSwift (macOS 10.14.4) -- the entry point the Swift
 * runtime uses to hand a class it has just laid out to the Objective-C
 * runtime.
 *
 * Swift checks for it before deciding how to set up a class whose superclass
 * is an Objective-C class. When it is present, Swift computes the field
 * offsets and instance size against the superclass first
 * (initClassFieldOffsetVector, initObjCClass) and then calls this to realize
 * the result. When it is absent, Swift falls back to requiring the class to
 * have arrived with a fixed instance size already baked in, and a class
 * compiled for a newer deployment target has not:
 *
 *   class ZMJarvisManager does not have a fragile layout;
 *   the deployment target was newer than this OS
 *
 * which is fatal. Providing it is therefore not merely an optimisation -- it
 * selects the path that computes the layout instead of demanding one.
 *
 * By the time this runs Swift has already done the layout work, so what is
 * left is exactly what objc_readClassPair does: realize the class and
 * its metaclass, and give objc their methods.
 */
Class _objc_realizeClassFromSwift(Class cls, void *previously) {
    (void)previously;   /* the caller's bookkeeping, not ours */
    return objc_readClassPair(cls, NULL);
}
