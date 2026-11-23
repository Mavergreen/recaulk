/* spec: README.md "The kernel-fixes kext" -- the fix engine's pure parts: no kernel calls, so the host tests build
   them too (tests/kfix-engine-test.sh) */
#ifndef RECAULK_KFIX_ENGINE_H
#define RECAULK_KFIX_ENGINE_H
#include <sys/types.h>
#include <stdint.h>

/* what each fix's sysctl reports */
enum kf_state { KF_NOT_APPLIED = 0, KF_APPLIED = 1, KF_FOREIGN = 2 };

/* a byte patch: at anchor+offset (or, while anchor is NULL, at a fixed unslid address the fix knows) the kernel
   holds expect[0..len); applying writes replace[0..len) */
struct kf_patch {
	const char *name;
	uint8_t uuid[16];
	const char *anchor;
	uint64_t offset;
	const uint8_t *expect;
	const uint8_t *replace;
	size_t len;
};

/* 0 with *st KF_NOT_APPLIED (site holds expect) or KF_FOREIGN (site holds replace); otherwise ESRCH and *why */
int kf_check_patch(const struct kf_patch *p, const uint8_t *site, enum kf_state *st, const char **why);
/* 1 when the boot command line turns fix `name` off: recaulk_kfix=0, or a recaulk_kfix= list holding -name */
int kf_bootarg_disabled(const char *cmdline, const char *name);
int kf_uuid_eq(const uint8_t a[16], const uint8_t b[16]);
#endif
