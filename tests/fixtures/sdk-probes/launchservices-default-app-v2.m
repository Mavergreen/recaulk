#import <CoreServices/CoreServices.h>
CFURLRef probe(CFURLRef u) {
    return LSCopyDefaultApplicationURLForURL(u, kLSRolesAll, NULL);
}
