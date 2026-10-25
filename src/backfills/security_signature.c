#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <string.h>

/* platform: 10.9's Security exports SecKeyRawSign, though its SDK declares it for iOS only; weak, as
   it is an undeclared import */
extern OSStatus SecKeyRawSign(SecKeyRef key, SecPadding padding, const uint8_t *dataToSign, size_t dataToSignLen,
                              uint8_t *sig, size_t *sigLen) __attribute__((weak_import));

enum recaulk_sig_family { RECAULK_SIG_RSA_PKCS1V15, RECAULK_SIG_ECDSA_X962 };

struct recaulk_sig_algorithm {
	CFStringRef name;
	enum recaulk_sig_family family;
	size_t digest_len;
	const uint8_t *digest_info;
	size_t digest_info_len;
};

/* spec: RFC 8017 section 9.2, note 1 */
static const uint8_t di_sha1[] = {0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14};
static const uint8_t di_sha224[] = {0x30, 0x2d, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x04, 0x05, 0x00, 0x04, 0x1c};
static const uint8_t di_sha256[] = {0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20};
static const uint8_t di_sha384[] = {0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30};
static const uint8_t di_sha512[] = {0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40};

#define RSA_ALG(s, n, di) { CFSTR("algid:sign:RSA:digest-PKCS1v15:" s), RECAULK_SIG_RSA_PKCS1V15, n, di, sizeof di }
#define ECDSA_ALG(s, n) { CFSTR("algid:sign:ECDSA:digest-X962:" s), RECAULK_SIG_ECDSA_X962, n, NULL, 0 }

/* spec: PROVENANCE.md, "SecKeyCreateSignature", lists what is supported and what is refused */
static const struct recaulk_sig_algorithm *find_algorithm(CFTypeRef name) {
	static struct recaulk_sig_algorithm table[] = {
		RSA_ALG("SHA1", 20, di_sha1),
		RSA_ALG("SHA224", 28, di_sha224),
		RSA_ALG("SHA256", 32, di_sha256),
		RSA_ALG("SHA384", 48, di_sha384),
		RSA_ALG("SHA512", 64, di_sha512),
		ECDSA_ALG("SHA1", 20),
		ECDSA_ALG("SHA224", 28),
		ECDSA_ALG("SHA256", 32),
		ECDSA_ALG("SHA384", 48),
		ECDSA_ALG("SHA512", 64),
	};
	size_t i;
	if (!name || CFGetTypeID(name) != CFStringGetTypeID()) return NULL;
	for (i = 0; i < sizeof table / sizeof table[0]; i++)
		if (CFEqual(name, table[i].name)) return &table[i];
	return NULL;
}

static void set_error(CFErrorRef *error, CFIndex code, CFStringRef description) {
	if (!error) return;
	CFDictionaryRef info = NULL;
	if (description) {
		const void *k[] = {kCFErrorDescriptionKey};
		const void *v[] = {description};
		info = CFDictionaryCreate(kCFAllocatorSystemDefault, k, v, 1,
		                          &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	}
	*error = CFErrorCreate(kCFAllocatorSystemDefault, kCFErrorDomainOSStatus, code, info);
	if (info) CFRelease(info);
}

static int key_signs(SecKeyRef key, enum recaulk_sig_family family) {
	const CSSM_KEY *cssm = NULL;
	if (SecKeyGetCSSMKey(key, &cssm) != errSecSuccess || !cssm) return 0;
	if (cssm->KeyHeader.KeyClass != CSSM_KEYCLASS_PRIVATE_KEY) return 0;
	return cssm->KeyHeader.AlgorithmId ==
	       (family == RECAULK_SIG_RSA_PKCS1V15 ? CSSM_ALGID_RSA : CSSM_ALGID_ECDSA);
}

CFDataRef SecKeyCreateSignature(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef dataToSign, CFErrorRef *error) {
	const struct recaulk_sig_algorithm *alg;
	uint8_t input[19 + 64];
	const uint8_t *in;
	size_t in_len, sig_len;
	CFMutableDataRef sig;
	OSStatus status;

	if (!key || CFGetTypeID(key) != SecKeyGetTypeID() || !dataToSign || CFGetTypeID(dataToSign) != CFDataGetTypeID()) {
		set_error(error, errSecParam, CFSTR("SecKeyCreateSignature: a key and data to sign are required"));
		return NULL;
	}
	alg = find_algorithm(algorithm);
	if (!alg || !SecKeyRawSign || !key_signs(key, alg->family)) {
		set_error(error, errSecParam, CFSTR("SecKeyCreateSignature: algorithm not supported by the key"));
		return NULL;
	}
	in = CFDataGetBytePtr(dataToSign);
	in_len = (size_t)CFDataGetLength(dataToSign);
	sig_len = SecKeyGetBlockSize(key);
	if (alg->family == RECAULK_SIG_ECDSA_X962) {
		/* spec: Apple Security-58286.1.32 OSX/sec/Security/SecKeyAdaptors.c line 182 (10.13 on) */
		if (in_len != alg->digest_len) {
			set_error(error, errSecParam, CFSTR("SecKeyCreateSignature: bad digest size for signing with algorithm"));
			return NULL;
		}
	} else {
		/* spec: Apple Security db15acbe OSX/libsecurity_keychain/lib/SecKey.cpp lines 615-618 and 724-727:
		   a CDSA key, as every 10.9 key is, takes input up to the digest's length, under its OID */
		size_t tlen = alg->digest_info_len + in_len;
		if (in_len > alg->digest_len) {
			set_error(error, errSecParam, CFSTR("SecKeyCreateSignature: input longer than the algorithm's digest"));
			return NULL;
		}
		memcpy(input, alg->digest_info, alg->digest_info_len);
		input[1] = (uint8_t)(tlen - 2);
		input[alg->digest_info_len - 1] = (uint8_t)in_len;
		memcpy(input + alg->digest_info_len, in, in_len);
		in = input;
		in_len = tlen;
	}

	sig = CFDataCreateMutable(kCFAllocatorDefault, (CFIndex)sig_len);
	if (!sig) {
		set_error(error, errSecAllocate, NULL);
		return NULL;
	}
	CFDataSetLength(sig, (CFIndex)sig_len);
	status = SecKeyRawSign(key, alg->family == RECAULK_SIG_RSA_PKCS1V15 ? kSecPaddingPKCS1 : kSecPaddingNone,
	                       in, in_len, CFDataGetMutableBytePtr(sig), &sig_len);
	if (status != errSecSuccess) {
		CFRelease(sig);
		set_error(error, status, CFSTR("SecKeyCreateSignature: the key's signing operation failed"));
		return NULL;
	}
	CFDataSetLength(sig, (CFIndex)sig_len);
	return sig;
}
