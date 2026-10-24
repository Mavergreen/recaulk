#ifndef RECAULK_SECURITY_SECKEY_H
#define RECAULK_SECURITY_SECKEY_H

#include_next <Security/SecKey.h>

#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 101200

#ifdef __cplusplus
extern "C" {
#endif

/* spec: README.md, "Security"; declared as Apple's SecKey.h gives them */
typedef CFStringRef SecKeyAlgorithm;

extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA1;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA224;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA384;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA512;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureDigestPSSSHA1;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureDigestPSSSHA256;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureDigestPSSSHA384;
extern const SecKeyAlgorithm kSecKeyAlgorithmRSASignatureDigestPSSSHA512;
extern const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureDigestX962SHA1;
extern const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureDigestX962SHA224;
extern const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureDigestX962SHA256;
extern const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureDigestX962SHA384;
extern const SecKeyAlgorithm kSecKeyAlgorithmECDSASignatureDigestX962SHA512;

CFDataRef SecKeyCreateSignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef dataToSign, CFErrorRef *error);

#ifdef __cplusplus
}
#endif

#endif

#endif
