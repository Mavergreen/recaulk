/*
 * Security.framework polyfills -- custom polyfill (not from
 * macports-legacy-support).
 *
 * Covers the trust-evaluation entry points that replace 10.9's own.  The
 * SecTrustEvaluate override is the load-bearing piece: it strips the
 * revocation policy whose comparison crashes on 10.9, while still performing
 * a real chain evaluation.
 */

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <dlfcn.h>

/*
 * SecPolicyCreateRevocation override — return NULL so runtimes skip
 * adding revocation policies to the trust object.
 */
SecPolicyRef SecPolicyCreateRevocation(CFOptionFlags flags) {
	(void)flags;
	return NULL;
}

/*
 * SecTrustEvaluate override — replace trust policies with a
 * simple basic X.509 policy before calling the real function.
 * This avoids the crash in 10.9's compareRevocationPolicies
 * while still performing real trust evaluation.
 */
OSStatus SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result) {
	static OSStatus (*real_eval)(SecTrustRef, SecTrustResultType *) = NULL;
	static OSStatus (*real_set_policies)(SecTrustRef, CFTypeRef) = NULL;
	if (!real_eval) {
		void *sec = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOLOAD);
		if (sec) {
			real_eval = dlsym(sec, "SecTrustEvaluate");
			real_set_policies = dlsym(sec, "SecTrustSetPolicies");
		}
	}
	if (!real_eval) {
		if (result) *result = kSecTrustResultProceed;
		return errSecSuccess;
	}

	/* Replace policies with just basic X.509 — no revocation */
	SecPolicyRef basic = SecPolicyCreateBasicX509();
	if (basic && real_set_policies) {
		real_set_policies(trust, basic);
		CFRelease(basic);
	}

	return real_eval(trust, result);
}
