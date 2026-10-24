#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

bool SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error);
CFArrayRef SecTrustCopyCertificateChain(SecTrustRef trust);

static int failures, checks;
static int backfill_eval, backfill_chain;

static void check(int ok, const char *what) {
  checks++;
  if (!ok) {
    failures++;
    printf("FAIL: %s\n", what);
  }
}

static SecCertificateRef load(const char *dir, const char *name) {
  char path[1024];
  uint8_t buf[8192];
  snprintf(path, sizeof path, "%s/%s", dir, name);
  FILE *f = fopen(path, "rb");
  if (!f) { printf("FAIL: cannot read %s\n", path); exit(1); }
  size_t n = fread(buf, 1, sizeof buf, f);
  fclose(f);
  CFDataRef d = CFDataCreate(NULL, buf, (CFIndex)n);
  SecCertificateRef c = SecCertificateCreateWithData(NULL, d);
  CFRelease(d);
  if (!c) { printf("FAIL: %s is not a DER certificate\n", path); exit(1); }
  return c;
}

static SecTrustRef trust_for(SecCertificateRef leaf, SecCertificateRef anchor) {
  SecPolicyRef policy = SecPolicyCreateBasicX509();
  CFArrayRef certs = CFArrayCreate(NULL, (const void **)&leaf, 1, &kCFTypeArrayCallBacks);
  SecTrustRef trust = NULL;
  OSStatus s = SecTrustCreateWithCertificates(certs, policy, &trust);
  CFRelease(certs);
  CFRelease(policy);
  if (s != errSecSuccess || !trust) { printf("FAIL: SecTrustCreateWithCertificates returned %d\n", (int)s); exit(1); }
  if (anchor) {
    CFArrayRef anchors = CFArrayCreate(NULL, (const void **)&anchor, 1, &kCFTypeArrayCallBacks);
    SecTrustSetAnchorCertificates(trust, anchors);
    CFRelease(anchors);
  }
  return trust;
}

static void expect_chain(const char *label, SecTrustRef trust, SecCertificateRef c0, SecCertificateRef c1) {
  char what[256];
  CFArrayRef chain = SecTrustCopyCertificateChain(trust);
  snprintf(what, sizeof what, "%s: SecTrustCopyCertificateChain returns the chain", label);
  check(chain != NULL, what);
  if (!chain) return;
  snprintf(what, sizeof what, "%s: the chain is a CFArray the caller owns (CF_RETURNS_RETAINED)", label);
  check(CFGetTypeID(chain) == CFArrayGetTypeID() && CFGetRetainCount(chain) == 1, what);
  snprintf(what, sizeof what, "%s: the chain runs leaf to anchor, two certificates (got %ld)", label, (long)CFArrayGetCount(chain));
  check(CFArrayGetCount(chain) == 2 && CFEqual(CFArrayGetValueAtIndex(chain, 0), c0) && CFEqual(CFArrayGetValueAtIndex(chain, 1), c1), what);
  CFRelease(chain);
}

static void expect_failure(const char *label, SecTrustRef trust, long code) {
  char what[256];
  CFErrorRef err = NULL;
  bool ok = SecTrustEvaluateWithError(trust, &err);
  snprintf(what, sizeof what, "%s: SecTrustEvaluateWithError returns false", label);
  check(!ok, what);
  snprintf(what, sizeof what, "%s: a failed evaluation sets *error (SecTrust.h: the error will be set)", label);
  check(err != NULL, what);
  if (err) {
    snprintf(what, sizeof what, "%s: the error is in kCFErrorDomainOSStatus, as Apple's SecTrustCopyError makes it", label);
    check(CFGetTypeID(err) == CFErrorGetTypeID() && CFEqual(CFErrorGetDomain(err), kCFErrorDomainOSStatus), what);
    if (code) {
      snprintf(what, sizeof what, "%s: the error's code is %ld, the most serious failure (got %ld)", label, code, (long)CFErrorGetCode(err));
      check(CFErrorGetCode(err) == code, what);
    }
    CFStringRef desc = CFErrorCopyDescription(err);
    snprintf(what, sizeof what, "%s: the error describes the failure", label);
    check(desc && CFStringGetLength(desc) > 0, what);
    if (desc) CFRelease(desc);
    snprintf(what, sizeof what, "%s: the caller owns the one reference to the error (CF_RETURNS_RETAINED)", label);
    check(CFGetRetainCount(err) == 1, what);
    CFRelease(err);
  }
  snprintf(what, sizeof what, "%s: SecTrustEvaluateWithError fails with a NULL error pointer too", label);
  check(!SecTrustEvaluateWithError(trust, NULL), what);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: security_trust FIXTURE-DIR\n"); return 2; }
  alarm(120);
  void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOLOAD | RTLD_LAZY);
  backfill_eval = !(security && dlsym(security, "SecTrustEvaluateWithError"));
  backfill_chain = !(security && dlsym(security, "SecTrustCopyCertificateChain"));
  printf("SecTrustEvaluateWithError: %s\n", backfill_eval ? "Recaulk's back-fill" : "this macOS's own, forwarded");
  printf("SecTrustCopyCertificateChain: %s\n", backfill_chain ? "Recaulk's back-fill" : "this macOS's own, forwarded");

  SecCertificateRef root = load(argv[1], "trust-root.der");
  SecCertificateRef leaf = load(argv[1], "trust-leaf.der");
  SecCertificateRef expired = load(argv[1], "trust-leaf-expired.der");

  SecTrustRef t = trust_for(leaf, root);
  expect_chain("an unevaluated anchored chain", t, leaf, root);
  CFRelease(t);

  t = trust_for(leaf, root);
  CFErrorRef sentinel = CFErrorCreate(NULL, CFSTR("recaulk.test.sentinel"), 7, NULL);
  CFErrorRef err = sentinel;
  check(SecTrustEvaluateWithError(t, &err), "an anchored chain: SecTrustEvaluateWithError returns true");
  check(err == NULL, "an anchored chain: a trusted evaluation sets *error to NULL (SecTrust.h)");
  if (err && err != sentinel) CFRelease(err);
  CFRelease(sentinel);
  check(SecTrustEvaluateWithError(t, NULL), "an anchored chain: SecTrustEvaluateWithError returns true with a NULL error pointer");
  expect_chain("an evaluated anchored chain", t, leaf, root);
  CFRelease(t);

  t = trust_for(root, NULL);
  expect_failure("a self-signed root nobody trusts", t, errSecNotTrusted);
  CFRelease(t);

  t = trust_for(expired, root);
  expect_failure("an expired leaf under a trusted root", t, errSecCertificateExpired);
  expect_chain("an expired leaf under a trusted root", t, expired, root);
  CFRelease(t);

  check(SecTrustCopyCertificateChain(NULL) == NULL, "SecTrustCopyCertificateChain(NULL) returns NULL, as Apple's does");

  CFArrayRef none = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
  SecPolicyRef policy = SecPolicyCreateBasicX509();
  SecTrustRef empty = NULL;
  if (SecTrustCreateWithCertificates(none, policy, &empty) == errSecSuccess && empty) {
    CFArrayRef chain = SecTrustCopyCertificateChain(empty);
    check(chain == NULL, "an empty chain: SecTrustCopyCertificateChain returns NULL, not an empty array (Apple's returns a chain only when it holds a certificate)");
    if (chain) CFRelease(chain);
    if (backfill_eval) expect_failure("an empty chain", empty, 0);
    CFRelease(empty);
  } else {
    printf("an empty chain: this macOS refuses to create a trust without certificates\n");
  }
  CFRelease(policy);
  CFRelease(none);

  if (backfill_eval) {
    err = NULL;
    check(!SecTrustEvaluateWithError(NULL, &err), "a NULL trust: SecTrustEvaluateWithError returns false");
    check(err && CFEqual(CFErrorGetDomain(err), kCFErrorDomainOSStatus) && CFErrorGetCode(err) != 0,
          "a NULL trust: the error carries the evaluation's own OSStatus");
    if (err) CFRelease(err);
  }

  CFRelease(root);
  CFRelease(leaf);
  CFRelease(expired);
  printf("security_trust: %d of %d checks failed\n", failures, checks);
  if (failures) return 1;
  printf("security_trust: all passed\n");
  return 0;
}
