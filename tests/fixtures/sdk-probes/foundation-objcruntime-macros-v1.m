#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface Probe : NSObject
- (instancetype)initWithValue:(int)value NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END
