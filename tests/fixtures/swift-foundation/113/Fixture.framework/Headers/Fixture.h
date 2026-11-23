#import <Foundation/NSArray.h>
@class NSString;
NS_ASSUME_NONNULL_BEGIN
typedef NSString *FXKey NS_EXTENSIBLE_STRING_ENUM;
FOUNDATION_EXPORT FXKey const FXKeyA;
FOUNDATION_EXPORT FXKey const FXKeyB;
typedef NS_OPTIONS(NSUInteger, FXOptions) {
    FXOptA = 1,
    FXOptB = 2
};
typedef const struct CF_BRIDGED_TYPE(NSString) __FXRef * FXRef;
@interface FXThing : NSObject
@property (readonly, getter=isOpen) BOOL open;
@property (class, readonly, strong) id shared;
@property (copy) NSString *name;
@property (readonly, copy) NSString *title;
@property (nullable, readonly, copy) NSString *label;
@property (readonly) NSInteger onlyNew;
- (NSString *)onlyOld;
@property (readonly, copy) NSArray<NSString *> *names;
- (nullable NSArray<NSString *> *)componentsOf:(NSString *)s;
@end
@interface FXMutableThing : FXThing
@property (readwrite, copy) NSString *title;
@end
NS_ASSUME_NONNULL_END
