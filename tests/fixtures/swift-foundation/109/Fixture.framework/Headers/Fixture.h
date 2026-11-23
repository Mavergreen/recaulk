#import <Foundation/NSObject.h>
@class NSString, NSArray;
FOUNDATION_EXPORT NSString * const FXKeyA;
FOUNDATION_EXPORT NSString *const FXKeyB NS_AVAILABLE(10_6, 4_0);
enum {
    FXOptA = 1,
    FXOptB = 2
};
typedef NSUInteger FXOptions;
typedef const struct __FXRef * FXRef;
@interface FXThing : NSObject
- (BOOL)isOpen;
+ (id)shared;
- (NSString *)name;
- (void)setName:(NSString *)name;
- (NSString *)title;
- (NSString *)onlyOld;
- (NSArray *)names;
- (NSArray *)componentsOf:(NSString *)s;
@end
@interface FXThing (FXExtras)
- (NSString *)label;
@end
@interface FXMutableThing : FXThing
- (void)setTitle:(NSString *)title;
@end
