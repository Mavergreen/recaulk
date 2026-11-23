/* spec: README.md "The kernel-fixes kext" -- each fix in turn: on 13F1911 only (the running kernel's UUID), unless
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
#include "kfix.h"

extern int printf(const char *, ...);
extern boolean_t ml_set_interrupts_enabled(boolean_t);

/* platform: the 10.9 x86_64 kernel links at this address (ksymresolver's KERN_TEXT_BASE), and KASLR slides it
   in 1 MiB steps */
#define KF_KERN_TEXT_BASE ((vm_offset_t)0xffffff8000200000ULL)
#define KF_KASLR_ALIGN ((vm_offset_t)0x100000)
#define KF_CR0_WP 0x00010000UL

int kf_kqueue_scan_restart_state = KF_NOT_APPLIED;

static const struct {
	const struct kf_patch *patch;
	int *state;
} kf_fixes[] = {
	{ &kf_kqueue_scan_restart, &kf_kqueue_scan_restart_state },
};

/* Adapted from github.com/acidanthera/Lilu/blob/137b4d9deb7022bb97fa9899303934534ff20ec7/Lilu/Sources/kern_mach.cpp
   (BSD-3; NOTICE.md), by way of Wowfunhappy's gist: walk down from a kernel function to the Mach-O header whose
   first segment is __TEXT. The gist starts from IOLog; this kext links no IOKit, so it starts from printf. */
static vm_offset_t
kf_kernel_header(void)
{
	vm_offset_t tmp = (vm_offset_t)printf & ~(KF_KASLR_ALIGN - 1);
	while (tmp >= KF_KASLR_ALIGN) {
		if (*(uint32_t *)tmp == MH_MAGIC_64) {
			const struct segment_command_64 *sc =
			    (const struct segment_command_64 *)(tmp + sizeof(struct mach_header_64));
			if (strncmp(sc->segname, "__TEXT", sizeof sc->segname) == 0)
				return tmp;
		}
		tmp -= KF_KASLR_ALIGN;
	}
	return 0;
}

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

void
kf_apply_all(void)
{
	const char *cmdline = PE_state.bootArgs ? ((boot_args *)PE_state.bootArgs)->CommandLine : NULL;
	uint8_t uuid[16];
	char hex[33];
	vm_offset_t mh = kf_kernel_header();
	if (mh == 0 || rk_header_uuid((const void *)mh, uuid) != 0) {
		printf(KF_LOG "no fixes: cannot find the running kernel's Mach-O header or its UUID\n");
		return;
	}
	vm_offset_t slide = mh - KF_KERN_TEXT_BASE;
	unsigned known = 0;
	for (unsigned i = 0; i < sizeof kf_fixes / sizeof kf_fixes[0]; i++) {
		const struct kf_patch *p = kf_fixes[i].patch;
		enum kf_state st;
		const char *why = NULL;
		if (!kf_uuid_eq(uuid, p->uuid))
			continue;
		known++;
		if (kf_bootarg_disabled(cmdline, p->name)) {
			printf(KF_LOG "%s: disabled (boot-arg)\n", p->name);
			continue;
		}
		uint8_t *site = (uint8_t *)(p->offset + slide);
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
		kf_uuid_hex(hex, uuid);
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
