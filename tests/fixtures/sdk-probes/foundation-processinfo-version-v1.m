#import <Foundation/Foundation.h>
BOOL probe(NSProcessInfo *p) {
    NSOperatingSystemVersion floor = {10, 9, 5};
    return p.operatingSystemVersion.majorVersion >= 10 && [p isOperatingSystemAtLeastVersion:floor];
}
