#import <Foundation/NSObject.h>
@class NSString;
NS_ASSUME_NONNULL_BEGIN
@interface FXThing : NSObject
@property (readonly, getter=isOpen) BOOL open;
@property (class, readonly, strong) id shared;
@property (copy) NSString *name;
@property (readonly, copy) NSString *title;
@property (nullable, readonly, copy) NSString *label;
@property (readonly) NSInteger onlyNew;
- (NSString *)onlyOld;
@end
@interface FXMutableThing : FXThing
@property (readwrite, copy) NSString *title;
@end
NS_ASSUME_NONNULL_END
