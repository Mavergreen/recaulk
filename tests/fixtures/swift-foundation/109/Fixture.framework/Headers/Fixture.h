#if !defined(__FIXTURE__)
#define __FIXTURE__ 1
#import <Foundation/NSObject.h>
@class NSString, NSArray;
FOUNDATION_EXPORT NSString * const FXKeyA;
FOUNDATION_EXPORT NSString *const FXKeyB NS_AVAILABLE(10_6, 4_0);
FOUNDATION_EXPORT NSString * const FXPlainA;
FOUNDATION_EXPORT NSString * const FXKeyC;
FOUNDATION_EXPORT NSString *FXKeyD;
enum {
    FXOptA = 1,
    FXOptB = 2
};
typedef NSUInteger FXOptions;
typedef const struct __FXRef * FXRef;
@interface FXThing : NSObject
- (BOOL)isOpen;
+ (id)shared;
+ (instancetype)current;
- (NSString *)name;
- (void)setName:(NSString *)name;
- (NSString *)title;
- (NSString *)onlyOld;
- (NSString *)URL;
- (NSArray *)names;
- (NSArray *)componentsOf:(NSString *)s;
- (id)valueFor:(NSString *)key;
- (NSString *)summary;
- (NSString *)joined:(NSString *)sep;
- (void)setTag:(NSString *)tag;
@end
@interface FXThing (FXExtras)
- (NSString *)label;
@end
@interface FXThing (FXMore)
- (NSString *)tag;
@end
@interface FXMutableThing : FXThing
- (void)setTitle:(NSString *)title;
- (void)setURL:(NSString *)URL;
- (void)setNames:(NSArray *)names;
@end
#endif
