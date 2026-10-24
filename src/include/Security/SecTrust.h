#ifndef RECAULK_SECURITY_SECTRUST_H
#define RECAULK_SECURITY_SECTRUST_H

#include_next <Security/SecTrust.h>

#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 120000

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* spec: README.md, "Security"; declared as Apple's SecTrust.h gives them */
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101400
bool SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error);
#endif

CFArrayRef SecTrustCopyCertificateChain(SecTrustRef trust);

#ifdef __cplusplus
}
#endif

#endif

#endif
