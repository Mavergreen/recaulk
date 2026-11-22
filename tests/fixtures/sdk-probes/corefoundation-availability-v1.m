#import <Foundation/Foundation.h>
NS_CLASS_AVAILABLE(10_14, 12_0)
@interface ProbeNew : NSObject
@end
typedef NS_ENUM(NSInteger, ProbeKind) {
    ProbeKindOld = 0,
    ProbeKindNew NS_ENUM_AVAILABLE_MAC(10_12) = 1
};
@interface Probe : NSObject
- (void)a NS_AVAILABLE_MAC(10_14);
- (void)b NS_AVAILABLE_MAC(10_10_3);
- (void)c NS_DEPRECATED_MAC(10_6, 10_11);
- (void)d NS_AVAILABLE(10_15, 13_0);
- (void)e API_AVAILABLE(macos(10.12), ios(10.0));
- (void)f API_AVAILABLE(macos(10.15), ios(13.0), tvos(13.0), watchos(6.0)) API_UNAVAILABLE(macCatalyst);
- (void)g API_UNAVAILABLE(ios, tvos, watchos);
- (void)h API_DEPRECATED("use e", macos(10.6, 10.13));
- (void)i API_DEPRECATED_WITH_REPLACEMENT("e", macos(10.6, 10.13), ios(2.0, 11.0));
@end
