#import <Foundation/NSArray.h>
@class NSString;
NS_ASSUME_NONNULL_BEGIN
typedef NSString *FXKey NS_EXTENSIBLE_STRING_ENUM;
FOUNDATION_EXPORT FXKey const FXKeyA;
FOUNDATION_EXPORT FXKey const FXKeyB;
FOUNDATION_EXPORT const FXKey FXKeyC API_AVAILABLE(macos(10.9)) API_UNAVAILABLE(ios);
typedef NSString *FXPlain;
FOUNDATION_EXPORT FXPlain const FXPlainA;
typedef NS_OPTIONS(NSUInteger, FXOptions) {
    FXOptA = 1,
    FXOptB = 2
};
typedef const struct CF_BRIDGED_TYPE(NSString) __FXRef * FXRef;
@interface FXThing : NSObject
@property (readonly, getter=isOpen) BOOL open;
@property (class, readonly, strong) id shared;
@property (class, readonly, strong) FXThing *current;
@property (copy) NSString *name;
@property (readonly, copy) NSString *title;
@property (nullable, readonly, copy) NSString *label;
@property (readonly) NSInteger onlyNew;
@property (readonly, copy) NSString *URL;
- (NSString *)onlyOld;
@property (readonly, copy) NSArray<NSString *> *names;
- (nullable NSArray<NSString *> *)componentsOf:(NSString *)s;
- (nullable id)valueFor:(FXKey)key;
@property (readonly, copy) NSString *summary;
- (NSString *)joined:(NSString *)sep;
@property (copy) NSString *tag;
@end
@interface FXMutableThing : FXThing
@property (readwrite, copy) NSString *title;
@property (copy) NSString *URL;
@property (readwrite, copy) NSArray<NSString *> *names;
@end
NS_ASSUME_NONNULL_END
