#import <Foundation/NSObject.h>
@class NSString;
@interface FXThing : NSObject
- (BOOL)isOpen;
+ (id)shared;
- (NSString *)name;
- (void)setName:(NSString *)name;
- (NSString *)title;
- (NSString *)onlyOld;
@end
@interface FXThing (FXExtras)
- (NSString *)label;
@end
@interface FXMutableThing : FXThing
- (void)setTitle:(NSString *)title;
@end
