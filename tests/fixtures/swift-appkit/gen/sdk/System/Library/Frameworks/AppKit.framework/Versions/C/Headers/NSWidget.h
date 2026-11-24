#import <Foundation/NSObject.h>

@interface NSWidget : NSObject
- (NSString *)title;
- (NSUInteger)mask;
- (BOOL)isOpen;
- (void)setOpen:(BOOL)flag;
- (NSString *)name;
@end
