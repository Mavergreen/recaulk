#import <objc/NSObject.h>

extern "C" { int rc_cxx_ctor_count, rc_cxx_dtor_count; }

struct RCTracker {
    RCTracker() { rc_cxx_ctor_count++; }
    ~RCTracker() { rc_cxx_dtor_count++; }
};

@interface RCCxxParent : NSObject { RCTracker tracker; }
@end
@implementation RCCxxParent
@end

@interface RCLazyCxx : NSObject { RCTracker tracker; }
@end
@implementation RCLazyCxx
@end
