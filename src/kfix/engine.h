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

/* ---- hooks: a call's rel32 retargeted to a trampoline in padding ---- */
/* The address of the one `e8 rel32` in fn[0..fnlen) (at fn_addr) whose destination is target and which before[]
   immediately precedes; zero or several give ESRCH and *why. */
int kf_find_call(const uint8_t *fn, size_t fnlen, uint64_t fn_addr, uint64_t target, const uint8_t *before,
    size_t nbefore, uint64_t *call_addr, const char **why);
/* 1 when [addr, addr+len) lies within one 64-byte cache line, where a store is atomic (Intel SDM vol. 3, 8.1.1) */
int kf_store_ok(uint64_t addr, size_t len);
/* the rel32 from next_ip to target; ERANGE beyond +-2 GiB */
int kf_rel32(uint64_t next_ip, uint64_t target, int32_t *disp);
/* 1 when pre[0] is a ret (0xc3) and pre[1..need] are all NOPs (0x90): padding no path executes */
int kf_gap_ok(const uint8_t *pre, size_t need);
/* jmp [rip+0] then handler: 14 bytes */
#define KF_TRAMPOLINE_LEN 14
void kf_trampoline(uint8_t out[KF_TRAMPOLINE_LEN], uint64_t handler);
#endif
