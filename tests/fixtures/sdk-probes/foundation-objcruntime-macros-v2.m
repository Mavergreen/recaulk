#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef NSString *ProbeKey NS_STRING_ENUM;
typedef NSString *ProbeName NS_EXTENSIBLE_STRING_ENUM;
typedef NSInteger ProbeCode NS_TYPED_ENUM;
typedef NSInteger ProbeLevel NS_TYPED_EXTENSIBLE_ENUM;
extern ProbeKey const ProbeKeyFirst;
NS_SWIFT_NAME(ProbeThing)
@interface Probe : NSObject
- (instancetype)initWithValue:(int)value NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)each:(void (NS_NOESCAPE ^)(id))block NS_SWIFT_NAME(forEach(_:));
- (BOOL)check:(NSError **)error NS_SWIFT_NOTHROW;
- (void)hidden NS_REFINED_FOR_SWIFT;
- (void)gone NS_SWIFT_UNAVAILABLE("use each:");
@end
NS_ASSUME_NONNULL_END
