#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

CFDataRef SecKeyCreateSignature(SecKeyRef key, CFStringRef algorithm, CFDataRef dataToSign, CFErrorRef *error);
/* platform: 10.9's Security exports SecKeyRawVerify, though its SDK declares it for iOS only */
OSStatus SecKeyRawVerify(SecKeyRef key, SecPadding padding, const uint8_t *signedData, size_t signedDataLen,
                         const uint8_t *sig, size_t sigLen);

static int failures, checks;
static void fails_with(const char *label, SecKeyRef key, CFStringRef alg, CFDataRef data, long code);
static int backfill;

static void check(int ok, const char *what) {
  checks++;
  if (!ok) {
    failures++;
    printf("FAIL: %s\n", what);
  }
}

static void keypair(CFStringRef type, int bits, SecKeyRef *pub, SecKeyRef *priv) {
  CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &bits);
  const void *k[] = {kSecAttrKeyType, kSecAttrKeySizeInBits, kSecAttrIsPermanent};
  const void *v[] = {type, n, kCFBooleanFalse};
  CFDictionaryRef d = CFDictionaryCreate(NULL, k, v, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  OSStatus s = SecKeyGeneratePair(d, pub, priv);
  CFRelease(d);
  CFRelease(n);
  if (s != errSecSuccess) {
    printf("FAIL: SecKeyGeneratePair(%d bits) returned %d, so nothing can be signed\n", bits, (int)s);
    exit(1);
  }
}

struct digest {
  const char *name;
  size_t len;
  int transform_type;
  const uint8_t *der;
  size_t der_len;
};

/* spec: RFC 8017 section 9.2, note 1, gives these DigestInfo prefixes byte for byte */
static const uint8_t di_sha1[] = {0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14};
static const uint8_t di_sha224[] = {0x30, 0x2d, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x04, 0x05, 0x00, 0x04, 0x1c};
static const uint8_t di_sha256[] = {0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20};
static const uint8_t di_sha384[] = {0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30};
static const uint8_t di_sha512[] = {0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40};

static const struct digest SHA1 = {"SHA1", 20, 1, di_sha1, sizeof di_sha1};
static const struct digest SHA224 = {"SHA224", 28, 224, di_sha224, sizeof di_sha224};
static const struct digest SHA256 = {"SHA256", 32, 256, di_sha256, sizeof di_sha256};
static const struct digest SHA384 = {"SHA384", 48, 384, di_sha384, sizeof di_sha384};
static const struct digest SHA512 = {"SHA512", 64, 512, di_sha512, sizeof di_sha512};

static CFDataRef digest_of(const struct digest *d, const char *message) {
  uint8_t out[64];
  CC_LONG n = (CC_LONG)strlen(message);
  switch (d->len) {
    case 20: CC_SHA1(message, n, out); break;
    case 28: CC_SHA224(message, n, out); break;
    case 32: CC_SHA256(message, n, out); break;
    case 48: CC_SHA384(message, n, out); break;
    default: CC_SHA512(message, n, out); break;
  }
  return CFDataCreate(NULL, out, (CFIndex)d->len);
}

static int transform_verifies(SecKeyRef pub, const struct digest *d, CFDataRef digest, CFDataRef sig) {
  CFErrorRef e = NULL;
  SecTransformRef t = SecVerifyTransformCreate(pub, sig, &e);
  if (!t) return 0;
  int ok = SecTransformSetAttribute(t, kSecInputIsAttributeName, kSecInputIsDigest, &e) &&
           SecTransformSetAttribute(t, kSecDigestTypeAttribute, d->transform_type == 1 ? kSecDigestSHA1 : kSecDigestSHA2, &e);
  if (ok && d->transform_type != 1) {
    int bits = d->transform_type;
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &bits);
    ok = SecTransformSetAttribute(t, kSecDigestLengthAttribute, n, &e);
    CFRelease(n);
  }
  ok = ok && SecTransformSetAttribute(t, kSecTransformInputAttributeName, digest, &e);
  CFTypeRef r = ok ? SecTransformExecute(t, &e) : NULL;
  ok = r == kCFBooleanTrue;
  if (r) CFRelease(r);
  if (e) CFRelease(e);
  CFRelease(t);
  return ok;
}

static int raw_verifies_rsa(SecKeyRef pub, const struct digest *d, CFDataRef digest, CFDataRef sig) {
  uint8_t info[100];
  memcpy(info, d->der, d->der_len);
  memcpy(info + d->der_len, CFDataGetBytePtr(digest), d->len);
  return SecKeyRawVerify(pub, kSecPaddingPKCS1, info, d->der_len + d->len, CFDataGetBytePtr(sig), (size_t)CFDataGetLength(sig)) == errSecSuccess;
}

static int raw_verifies_ec(SecKeyRef pub, CFDataRef digest, CFDataRef sig) {
  return SecKeyRawVerify(pub, kSecPaddingNone, CFDataGetBytePtr(digest), (size_t)CFDataGetLength(digest),
                         CFDataGetBytePtr(sig), (size_t)CFDataGetLength(sig)) == errSecSuccess;
}

static void rsa_input_of_length(SecKeyRef pub, SecKeyRef priv, size_t len, int signs) {
  char what[256];
  uint8_t in[200], info[256];
  size_t i;
  for (i = 0; i < len; i++) in[i] = (uint8_t)(i * 7 + 1);
  CFDataRef data = CFDataCreate(NULL, in, (CFIndex)len);
  CFErrorRef err = NULL;
  CFDataRef sig = SecKeyCreateSignature(priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256"), data, &err);
  if (signs) {
    snprintf(what, sizeof what, "RSA SHA-256 given a %zu-byte input: SecKeyCreateSignature signs it, as Apple's does", len);
    check(sig != NULL, what);
    if (sig) {
      /* spec: RFC 8017 appendix A.2.4, DigestInfo ::= SEQUENCE { SEQUENCE { OID, NULL }, OCTET STRING } */
      memcpy(info, di_sha256, sizeof di_sha256);
      info[1] = (uint8_t)(sizeof di_sha256 - 2 + len);
      info[sizeof di_sha256 - 1] = (uint8_t)len;
      memcpy(info + sizeof di_sha256, in, len);
      snprintf(what, sizeof what, "RSA SHA-256 given a %zu-byte input: SecKeyRawVerify accepts it as PKCS#1 v1.5 over DigestInfo(SHA-256 OID, input)", len);
      check(SecKeyRawVerify(pub, kSecPaddingPKCS1, info, sizeof di_sha256 + len, CFDataGetBytePtr(sig), (size_t)CFDataGetLength(sig)) == errSecSuccess, what);
      CFRelease(sig);
    }
    if (err) CFRelease(err);
  } else {
    if (sig) CFRelease(sig);
    if (err) CFRelease(err);
    snprintf(what, sizeof what, "RSA SHA-256 given a %zu-byte input, whose DigestInfo is too long to encode", len);
    fails_with(what, priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256"), data, errSecParam);
  }
  CFRelease(data);
}

static CFDataRef tampered(CFDataRef sig) {
  CFMutableDataRef t = CFDataCreateMutableCopy(NULL, 0, sig);
  CFDataGetMutableBytePtr(t)[CFDataGetLength(t) / 2] ^= 0x5a;
  return t;
}

static void sign_and_verify(const char *label, int rsa, SecKeyRef pub, SecKeyRef priv, CFStringRef alg, const struct digest *d) {
  char what[256];
  CFDataRef digest = digest_of(d, "recaulk signs this message");
  CFErrorRef sentinel = CFErrorCreate(NULL, CFSTR("recaulk.test.sentinel"), 7, NULL);
  CFErrorRef err = sentinel;
  CFDataRef sig = SecKeyCreateSignature(priv, alg, digest, &err);
  snprintf(what, sizeof what, "%s %s: SecKeyCreateSignature returns a signature", label, d->name);
  check(sig != NULL, what);
  snprintf(what, sizeof what, "%s %s: a successful SecKeyCreateSignature leaves *error untouched, as Apple's does", label, d->name);
  check(err == sentinel, what);
  if (err != sentinel && err) CFRelease(err);
  CFRelease(sentinel);
  if (sig) {
    CFDataRef bad = tampered(sig);
    snprintf(what, sizeof what, "%s %s: the signature is a CFData the caller owns", label, d->name);
    check(CFGetTypeID(sig) == CFDataGetTypeID() && CFGetRetainCount(sig) == 1, what);
    snprintf(what, sizeof what, "%s %s: SecVerifyTransform accepts the signature over the digest", label, d->name);
    check(transform_verifies(pub, d, digest, sig), what);
    snprintf(what, sizeof what, "%s %s: SecVerifyTransform rejects a tampered signature", label, d->name);
    check(!transform_verifies(pub, d, digest, bad), what);
    if (rsa) {
      snprintf(what, sizeof what, "%s %s: SecKeyRawVerify accepts it as PKCS#1 v1.5 over the RFC 8017 DigestInfo", label, d->name);
      check(raw_verifies_rsa(pub, d, digest, sig), what);
      snprintf(what, sizeof what, "%s %s: SecKeyRawVerify rejects a tampered signature", label, d->name);
      check(!raw_verifies_rsa(pub, d, digest, bad), what);
    } else {
      snprintf(what, sizeof what, "%s %s: SecKeyRawVerify accepts it as an X9.62 ECDSA signature of the digest", label, d->name);
      check(raw_verifies_ec(pub, digest, sig), what);
      snprintf(what, sizeof what, "%s %s: SecKeyRawVerify rejects a tampered signature", label, d->name);
      check(!raw_verifies_ec(pub, digest, bad), what);
    }
    CFRelease(bad);
    CFRelease(sig);
  }
  err = NULL;
  sig = SecKeyCreateSignature(priv, alg, digest, NULL);
  snprintf(what, sizeof what, "%s %s: SecKeyCreateSignature signs with a NULL error pointer too", label, d->name);
  check(sig != NULL, what);
  if (sig) CFRelease(sig);
  CFRelease(digest);
}

static void fails_with(const char *label, SecKeyRef key, CFStringRef alg, CFDataRef data, long code) {
  char what[256];
  CFErrorRef err = NULL;
  CFDataRef sig = SecKeyCreateSignature(key, alg, data, &err);
  snprintf(what, sizeof what, "%s: SecKeyCreateSignature returns NULL", label);
  check(sig == NULL, what);
  if (sig) CFRelease(sig);
  snprintf(what, sizeof what, "%s: a failed SecKeyCreateSignature sets *error (SecKey.h: on error, populated)", label);
  check(err != NULL, what);
  if (err) {
    snprintf(what, sizeof what, "%s: the error is in kCFErrorDomainOSStatus, as Apple's SecError makes it", label);
    check(CFGetTypeID(err) == CFErrorGetTypeID() && CFEqual(CFErrorGetDomain(err), kCFErrorDomainOSStatus), what);
    if (code) {
      snprintf(what, sizeof what, "%s: the error's code is %ld (got %ld)", label, code, (long)CFErrorGetCode(err));
      check(CFErrorGetCode(err) == code, what);
    }
    snprintf(what, sizeof what, "%s: the caller owns the one reference to the error", label);
    check(CFGetRetainCount(err) == 1, what);
    CFRelease(err);
  }
  sig = SecKeyCreateSignature(key, alg, data, NULL);
  snprintf(what, sizeof what, "%s: SecKeyCreateSignature fails with a NULL error pointer too", label);
  check(sig == NULL, what);
  if (sig) CFRelease(sig);
}

static void *fail_alloc(CFIndex size, CFOptionFlags hint, void *info) {
  (void)size; (void)hint; (void)info;
  return NULL;
}

static void allocation_fails(SecKeyRef priv, CFDataRef digest) {
  CFAllocatorContext ctx = {0, NULL, NULL, NULL, NULL, fail_alloc, NULL, NULL, NULL};
  CFAllocatorRef failing = CFAllocatorCreate(kCFAllocatorSystemDefault, &ctx);
  CFAllocatorRef previous = CFRetain(CFAllocatorGetDefault());
  CFErrorRef err = NULL;
  CFAllocatorSetDefault(failing);
  CFDataRef sig = SecKeyCreateSignature(priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256"), digest, &err);
  CFDataRef sig2 = SecKeyCreateSignature(priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256"), digest, NULL);
  CFAllocatorSetDefault(previous);
  CFRelease(previous);
  check(sig == NULL && sig2 == NULL, "out of memory: SecKeyCreateSignature returns NULL when the default allocator fails");
  check(err != NULL && CFEqual(CFErrorGetDomain(err), kCFErrorDomainOSStatus) && CFErrorGetCode(err) == errSecAllocate,
        "out of memory: the error is errSecAllocate in kCFErrorDomainOSStatus");
  if (err) CFRelease(err);
  if (sig) CFRelease(sig);
  if (sig2) CFRelease(sig2);
  CFRelease(failing);
}

int main(void) {
  SecKeyRef rsa_pub, rsa_priv, p256_pub, p256_priv, p384_pub, p384_priv, p521_pub, p521_priv;
  void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOLOAD | RTLD_LAZY);
  alarm(120);
  backfill = !(security && dlsym(security, "SecKeyCreateSignature"));
  printf("SecKeyCreateSignature: %s\n", backfill ? "Recaulk's back-fill" : "this macOS's own, forwarded");

  keypair(kSecAttrKeyTypeRSA, 2048, &rsa_pub, &rsa_priv);
  keypair(kSecAttrKeyTypeEC, 256, &p256_pub, &p256_priv);
  keypair(kSecAttrKeyTypeEC, 384, &p384_pub, &p384_priv);
  keypair(kSecAttrKeyTypeEC, 521, &p521_pub, &p521_priv);

  sign_and_verify("RSA-2048 PKCS#1 v1.5", 1, rsa_pub, rsa_priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA1"), &SHA1);
  sign_and_verify("RSA-2048 PKCS#1 v1.5", 1, rsa_pub, rsa_priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA224"), &SHA224);
  sign_and_verify("RSA-2048 PKCS#1 v1.5", 1, rsa_pub, rsa_priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256"), &SHA256);
  sign_and_verify("RSA-2048 PKCS#1 v1.5", 1, rsa_pub, rsa_priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA384"), &SHA384);
  sign_and_verify("RSA-2048 PKCS#1 v1.5", 1, rsa_pub, rsa_priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA512"), &SHA512);
  sign_and_verify("P-256 ECDSA X9.62", 0, p256_pub, p256_priv, CFSTR("algid:sign:ECDSA:digest-X962:SHA1"), &SHA1);
  sign_and_verify("P-256 ECDSA X9.62", 0, p256_pub, p256_priv, CFSTR("algid:sign:ECDSA:digest-X962:SHA224"), &SHA224);
  sign_and_verify("P-256 ECDSA X9.62", 0, p256_pub, p256_priv, CFSTR("algid:sign:ECDSA:digest-X962:SHA256"), &SHA256);
  sign_and_verify("P-256 ECDSA X9.62", 0, p256_pub, p256_priv, CFSTR("algid:sign:ECDSA:digest-X962:SHA384"), &SHA384);
  sign_and_verify("P-256 ECDSA X9.62", 0, p256_pub, p256_priv, CFSTR("algid:sign:ECDSA:digest-X962:SHA512"), &SHA512);
  sign_and_verify("P-384 ECDSA X9.62", 0, p384_pub, p384_priv, CFSTR("algid:sign:ECDSA:digest-X962:SHA384"), &SHA384);
  sign_and_verify("P-521 ECDSA X9.62", 0, p521_pub, p521_priv, CFSTR("algid:sign:ECDSA:digest-X962:SHA512"), &SHA512);

  CFDataRef d256 = digest_of(&SHA256, "recaulk signs this message");
  CFDataRef d20 = digest_of(&SHA1, "recaulk signs this message");
  fails_with("an RSA algorithm with an EC key", p256_priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256"), d256, backfill ? errSecParam : 0);
  fails_with("an ECDSA algorithm with an RSA key", rsa_priv, CFSTR("algid:sign:ECDSA:digest-X962:SHA256"), d256, backfill ? errSecParam : 0);
  fails_with("signing with an RSA public key", rsa_pub, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256"), d256, backfill ? errSecParam : 0);
  fails_with("signing with an EC public key", p256_pub, CFSTR("algid:sign:ECDSA:digest-X962:SHA256"), d256, backfill ? errSecParam : 0);
  fails_with("an algorithm Apple does not define", rsa_priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA3"), d256, errSecParam);
  rsa_input_of_length(rsa_pub, rsa_priv, 0, 1);
  rsa_input_of_length(rsa_pub, rsa_priv, 20, 1);
  rsa_input_of_length(rsa_pub, rsa_priv, 107, 1);
  rsa_input_of_length(rsa_pub, rsa_priv, 108, 0);
  fails_with("ECDSA SHA-256 given a 20-byte digest", p256_priv, CFSTR("algid:sign:ECDSA:digest-X962:SHA256"), d20, errSecParam);

  if (backfill) {
    fails_with("RSA-PSS SHA-256, which the back-fill does not implement", rsa_priv, CFSTR("algid:sign:RSA:digest-PSS:SHA256:SHA256:32"), d256, errSecParam);
    fails_with("RSA-PSS SHA-384, which the back-fill does not implement", rsa_priv, CFSTR("algid:sign:RSA:digest-PSS:SHA384:SHA384:48"), d256, errSecParam);
    fails_with("RSA-PSS SHA-512, which the back-fill does not implement", rsa_priv, CFSTR("algid:sign:RSA:digest-PSS:SHA512:SHA512:64"), d256, errSecParam);
    fails_with("a NULL key", NULL, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256"), d256, errSecParam);
    fails_with("NULL data", rsa_priv, CFSTR("algid:sign:RSA:digest-PKCS1v15:SHA256"), NULL, errSecParam);
    fails_with("a NULL algorithm", rsa_priv, NULL, d256, errSecParam);
    allocation_fails(rsa_priv, d256);
  } else {
    CFErrorRef err = NULL;
    CFDataRef sig = SecKeyCreateSignature(rsa_priv, CFSTR("algid:sign:RSA:digest-PSS:SHA256:SHA256:32"), d256, &err);
    check(sig != NULL && CFDataGetLength(sig) == 256, "this macOS's own SecKeyCreateSignature signs RSA-PSS SHA-256");
    if (sig) CFRelease(sig);
    if (err) CFRelease(err);
  }
  CFRelease(d256);
  CFRelease(d20);

  printf("security_signatures: %d of %d checks failed\n", failures, checks);
  if (failures) return 1;
  printf("security_signatures: all passed\n");
  return 0;
}
