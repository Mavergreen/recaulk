// weak: _LSCopyDefaultApplicationURLForURL
#import <CoreServices/CoreServices.h>
CFURLRef probe(CFURLRef u) {
    if (&LSCopyDefaultApplicationURLForURL == NULL) { return NULL; }
    return LSCopyDefaultApplicationURLForURL(u, kLSRolesAll, NULL);
}
