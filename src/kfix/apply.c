/* spec: README.md "The kernel-fixes kext" -- each fix in turn, its site found through /mach_kernel's symbols (whose
   UUID matches the running kernel's): on 13F1911 only, unless
   the boot-arg turns it off, and only over the bytes it expects; its replacement already there means another
   kext applied it. Kernel text is written with interrupts off and CR0.WP clear, as KQueueScanContinuePatch did. */
#include <sys/types.h>
#include <sys/errno.h>
#include <string.h>
#include <mach/mach_types.h>
#include <mach-o/loader.h>
#include <i386/proc_reg.h>
#include <kern/debug.h>
#include <pexpert/pexpert.h>
#include <pexpert/i386/boot.h>
#include "core.h"
#include "kresolve.h"
#include "kfix.h"

extern int printf(const char *, ...);
extern boolean_t ml_set_interrupts_enabled(boolean_t);

#define KF_CR0_WP 0x00010000UL

int kf_kqueue_scan_restart_state = KF_NOT_APPLIED;

static const struct {
	const struct kf_patch *patch;
	int *state;
} kf_fixes[] = {
	{ &kf_kqueue_scan_restart, &kf_kqueue_scan_restart_state },
};

/* KQueueScanContinuePatch's write: this CPU's interrupts off, CR0.WP clear, copy, restore, each step checked */
static int
kf_write_text(void *dst, const void *src, size_t len)
{
	boolean_t intr = ml_set_interrupts_enabled(FALSE);
	uintptr_t cr0 = get_cr0();
	if (cr0 & KF_CR0_WP) {
		set_cr0(cr0 & ~KF_CR0_WP);
		if (get_cr0() & KF_CR0_WP) {
			ml_set_interrupts_enabled(intr);
			return EIO;
		}
	}
	memcpy(dst, src, len);
	if (cr0 & KF_CR0_WP) {
		set_cr0(get_cr0() | KF_CR0_WP);
		if (!(get_cr0() & KF_CR0_WP))
			panic(KF_LOG "CR0.WP would not set again after writing kernel text");
	}
	ml_set_interrupts_enabled(intr);
	return memcmp(dst, src, len) == 0 ? 0 : EIO;
}

static void
kf_uuid_hex(char out[33], const uint8_t u[16])
{
	static const char h[] = "0123456789abcdef";
	for (int i = 0; i < 16; i++) {
		out[2 * i] = h[u[i] >> 4];
		out[2 * i + 1] = h[u[i] & 15];
	}
	out[32] = '\0';
}

#ifdef RECAULK_KFIX_UUID_FLIP
#define KF_UUID_FLIP 1	/* tests/kfix-runtime-test.sh's uuid_variant: the table names another kernel */
#else
#define KF_UUID_FLIP 0
#endif

#define KF_NFIX (sizeof kf_fixes / sizeof kf_fixes[0])

void
kf_apply_all(void)
{
	const char *cmdline = PE_state.bootArgs ? ((boot_args *)PE_state.bootArgs)->CommandLine : NULL;
	/* the fixes' anchors, then two symbols whose live addresses fix the slide */
	struct rk_sym want[KF_NFIX + 2];
	uint64_t live[KF_NFIX + 2];
	struct rk_kernel k;
	uint64_t slide;
	const char *why = NULL;
	char hex[33];
	unsigned i, known = 0;
	int err;

	for (i = 0; i < KF_NFIX; i++) {
		want[i] = (struct rk_sym){ kf_fixes[i].patch->anchor, 0, 0 };
		live[i] = 0;
	}
	want[i] = (struct rk_sym){ "_printf", 0, 0 };
	live[i++] = (uint64_t)(uintptr_t)&printf;
	want[i] = (struct rk_sym){ "_panic", 0, 0 };
	live[i++] = (uint64_t)(uintptr_t)&panic;
	if ((err = rk_resolve_live(want, live, i, &k, &slide, &why)) != 0) {
		printf(KF_LOG "no fixes: cannot read the running kernel's symbols (%s, error %d)\n", why, err);
		return;
	}
	k.uuid[0] ^= KF_UUID_FLIP;
	for (i = 0; i < KF_NFIX; i++) {
		const struct kf_patch *p = kf_fixes[i].patch;
		enum kf_state st;
		if (!kf_uuid_eq(k.uuid, p->uuid))
			continue;
		known++;
		if (kf_bootarg_disabled(cmdline, p->name)) {
			printf(KF_LOG "%s: disabled (boot-arg)\n", p->name);
			continue;
		}
		uint64_t at = want[i].value + p->offset;
		if (!want[i].found || at < k.text_vmaddr || at + p->len > k.text_vmaddr + k.text_vmsize) {
			printf(KF_LOG "%s: refused (%s+0x%llx is not in the kernel's __TEXT)\n", p->name, p->anchor,
			    (unsigned long long)p->offset);
			continue;
		}
		uint8_t *site = (uint8_t *)(uintptr_t)(at + slide);
		if (kf_check_patch(p, site, &st, &why) != 0) {
			printf(KF_LOG "%s: refused (%s)\n", p->name, why);
			continue;
		}
		if (st == KF_FOREIGN) {
			*kf_fixes[i].state = KF_FOREIGN;
			printf(KF_LOG "%s: already applied (by another kext)\n", p->name);
			continue;
		}
		if (kf_write_text(site, p->replace, p->len) != 0) {
			printf(KF_LOG "%s: refused (the write did not take)\n", p->name);
			continue;
		}
		*kf_fixes[i].state = KF_APPLIED;
		printf(KF_LOG "%s: applied\n", p->name);
	}
	if (known == 0) {
		kf_uuid_hex(hex, k.uuid);
		printf(KF_LOG "no fixes for this kernel (UUID %s)\n", hex);
	}
}

int
kf_any_applied(void)
{
	for (unsigned i = 0; i < sizeof kf_fixes / sizeof kf_fixes[0]; i++)
		if (*kf_fixes[i].state == KF_APPLIED)
			return 1;
	return 0;
}
