/* platform: LaunchServices is a subframework, reachable only from inside CoreServices' umbrella, so a
   program that names this header directly gets the umbrella, which then reaches this wrapper again. */
#if __has_include_next(<LaunchServices/LSInfo.h>)
#include_next <LaunchServices/LSInfo.h>
#else
#include <CoreServices/CoreServices.h>
#endif

#ifndef RECAULK_LAUNCHSERVICES_LSINFO_H
#define RECAULK_LAUNCHSERVICES_LSINFO_H

#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101000

#ifdef __cplusplus
extern "C" {
#endif

/* spec: README.md, "Declarations"; declared as Apple's LSInfo.h gives it */
CFURLRef LSCopyDefaultApplicationURLForURL(CFURLRef inURL, LSRolesMask inRoleMask, CFErrorRef *outError);

#ifdef __cplusplus
}
#endif

#endif

#endif
