// profile: swift-foundation
// spec: .superpowers/specs/2026-11-23-swift-foundation-recipes-design.md -- an Objective-C consumer built with
//       -Werror against the profile still compiles its subclasses that override getters it converts to properties
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
@interface RCObject : NSObject @end
@implementation RCObject
- (NSString *)description { return @"x"; }
- (NSString *)debugDescription { return @"y"; }
- (NSUInteger)hash { return 1; }
- (Class)superclass { return [super superclass]; }
@end
@interface RCURL : NSURL @end
@implementation RCURL
- (NSString *)absoluteString { return [super absoluteString]; }
- (BOOL)isFileURL { return NO; }
@end
@interface RCLocale : NSLocale @end
@implementation RCLocale
- (NSString *)localeIdentifier { return @"en"; }
@end
@interface RCOperation : NSOperation @end
@implementation RCOperation
- (BOOL)isFinished { return YES; }
- (BOOL)isConcurrent { return NO; }
- (void)main {}
@end
@interface RCMutableRequest : NSMutableURLRequest @end
@implementation RCMutableRequest
- (NSURL *)URL { return [super URL]; }
- (void)setURL:(NSURL *)u { [super setURL:u]; }
@end
static char key;
int use(NSURL *u, NSError *e, NSArray *a, CFStringRef s) {
  NSArray *c = [u pathComponents];
  NSDictionary *i = [e userInfo];
  objc_setAssociatedObject(a, &key, u, OBJC_ASSOCIATION_RETAIN);
  [a enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id o, NSUInteger n, BOOL *stop) { (void)o; (void)n; *stop = YES; }];
  return (int)[c count] + (int)[i count] + (u.fileURL ? 1 : 0) + (int)[[NSProcessInfo processInfo] processorCount]
       + (int)[(NSString *)s length] + (NSRectEdgeMinX == NSMinXEdge) + (NSDateComponentUndefined > 0);
}
NSUInteger subscripts(NSDictionary<NSString *, NSString *> *d, NSOrderedSet<NSString *> *o, NSArray<NSString *> *a) {
  return d[@"k"].length + o[0].length + a[0].length;
}
