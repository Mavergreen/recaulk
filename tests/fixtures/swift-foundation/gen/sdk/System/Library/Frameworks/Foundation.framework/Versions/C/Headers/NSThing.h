#import <Foundation/NSObject.h>
typedef NSUInteger NSThingEdge;
@interface NSThing : NSObject
- (BOOL)isFileURL;
- (NSString *)title;
- (NSString *)name;
- (NSString *)extra;
@end
@interface NSOther : NSObject
- (NSString *)name;
@end
