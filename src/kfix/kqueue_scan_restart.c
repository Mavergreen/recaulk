/* spec: README.md "The kernel-fixes kext" -- kqueue_scan_restart: when a kevent wait ends THREAD_RESTART
   (its kqueue torn down beneath it), 10.9's kqueue_scan_continue panics "invalid wait_result (3)"
   (xnu-2422.115.4 bsd/kern/kern_event.c, kqueue_scan_continue); newer xnu returns EBADF, and so does this.

   Ported from KQueueScanContinuePatch, by Wowfunhappy with assistance from krackers,
   https://gist.github.com/Wowfunhappy/8212f5bea4c601ac9a6297789f232321, which Wowfunhappy declared CC-0
   (that gist, comment 6488041). Kept: its 10.9.5 13F1911 site, bytes and replacement, and its method:
   find the kernel's base, check the bytes, interrupts off, CR0.WP clear, write, restore. kf_kernel_base()
   is adapted from Lilu's (see NOTICE.md). Added: the state the sysctl reports, and standing down when the
   replacement is already in place. */
#include <sys/types.h>
#include <sys/errno.h>
#include <string.h>
#include <mach/mach_types.h>
#include <mach-o/loader.h>
#include <i386/proc_reg.h>
#include <kern/debug.h>
#include "kfix.h"

extern int printf(const char *, ...);
extern boolean_t ml_get_interrupts_enabled(void);
extern boolean_t ml_set_interrupts_enabled(boolean_t);

/* platform: the 10.9 x86_64 kernel links at this address (ksymresolver's KERN_TEXT_BASE), and KASLR slides it
   in 1 MiB steps */
#define KF_KERN_TEXT_BASE ((vm_offset_t)0xffffff8000200000ULL)
#define KF_KASLR_ALIGN ((vm_offset_t)0x100000)
#define KF_CR0_WP 0x00010000UL

/* platform: 10.9.5 13F1911 (xnu-2422.115.15), unslid, from the gist (Hopper): the panic call's argument
   set-up, the call, and the `xor r12d, r12d` after it; the last 3 bytes stay, as a check of the far edge */
#define KQ_SITE ((vm_offset_t)0xffffff80005c7a9cULL)
#define KQ_WRITE 27
static const uint8_t kq_expect[30] = {
	0x48, 0x8d, 0x3d, 0xbb, 0xf3, 0x19, 0x00, /* lea rdi, [aSInvalidWaitre] */
	0x48, 0x8d, 0x35, 0x11, 0xf4, 0x19, 0x00, /* lea rsi, [aKqueuescancont] */
	0x44, 0x89, 0xfa,                         /* mov edx, r15d */
	0x30, 0xc0,                               /* xor al, al */
	0xe8, 0xbc, 0xb5, 0xc5, 0xff,             /* call _panic */
	0x45, 0x31, 0xe4,                         /* xor r12d, r12d */
	0x49, 0x8b, 0xb5,
};
/* mov r12d, 9 (EBADF, the error kqueue_scan_continue returns), then NOPs */
static const uint8_t kq_replace[7] = { 0x41, 0xbc, 0x09, 0x00, 0x00, 0x00, 0x90 };

/* the bytes as they are after the write: the replacement, NOP fill, the untouched tail */
static int
kq_is_replaced(const uint8_t *p)
{
	if (memcmp(p, kq_replace, sizeof kq_replace) != 0)
		return 0;
	for (unsigned i = sizeof kq_replace; i < KQ_WRITE; i++)
		if (p[i] != 0x90)
			return 0;
	return memcmp(p + KQ_WRITE, kq_expect + KQ_WRITE, sizeof kq_expect - KQ_WRITE) == 0;
}

/* Adapted from github.com/acidanthera/Lilu/blob/137b4d9deb7022bb97fa9899303934534ff20ec7/Lilu/Sources/kern_mach.cpp
   (BSD-3; NOTICE.md), by way of the gist: walk down from a kernel function to the Mach-O header whose first
   segment is __TEXT. The gist starts from IOLog; this kext links no IOKit, so it starts from printf. */
static vm_offset_t
kf_kernel_slide(void)
{
	vm_offset_t tmp = (vm_offset_t)printf & ~(KF_KASLR_ALIGN - 1);
	while (tmp >= KF_KASLR_ALIGN) {
		if (*(uint32_t *)tmp == MH_MAGIC_64) {
			const struct segment_command_64 *sc =
			    (const struct segment_command_64 *)(tmp + sizeof(struct mach_header_64));
			if (strncmp(sc->segname, "__TEXT", sizeof sc->segname) == 0)
				return tmp - KF_KERN_TEXT_BASE;
		}
		tmp -= KF_KASLR_ALIGN;
	}
	return (vm_offset_t)-1;
}

static void
kq_hex(char out[sizeof kq_expect * 3], const uint8_t *p)
{
	static const char h[] = "0123456789abcdef";
	for (unsigned i = 0; i < sizeof kq_expect; i++) {
		out[3 * i] = h[p[i] >> 4];
		out[3 * i + 1] = h[p[i] & 15];
		out[3 * i + 2] = i + 1 < sizeof kq_expect ? ' ' : '\0';
	}
}

void
kf_kqueue_scan_restart_apply(void)
{
	char hex[sizeof kq_expect * 3];
	vm_offset_t slide = kf_kernel_slide();
	if (slide == (vm_offset_t)-1) {
		printf(KF_LOG "kqueue_scan_restart: refused (no kernel Mach-O header below printf)\n");
		return;
	}
	uint8_t *site = (uint8_t *)(KQ_SITE + slide);
	if (kq_is_replaced(site)) {
		kf_kqueue_scan_restart_state = KF_FOREIGN;
		printf(KF_LOG "kqueue_scan_restart: already applied (by another kext)\n");
		return;
	}
	if (memcmp(site, kq_expect, sizeof kq_expect) != 0) {
		kq_hex(hex, site);
		printf(KF_LOG "kqueue_scan_restart: refused (not 13F1911's bytes at the site: %s)\n", hex);
		return;
	}
	kq_hex(hex, site);
	printf(KF_LOG "kqueue_scan_restart: before: %s\n", hex);

	boolean_t intr = ml_set_interrupts_enabled(FALSE);
	uintptr_t cr0 = get_cr0();
	if (cr0 & KF_CR0_WP) {
		set_cr0(cr0 & ~KF_CR0_WP);
		if (get_cr0() & KF_CR0_WP) {
			ml_set_interrupts_enabled(intr);
			printf(KF_LOG "kqueue_scan_restart: refused (CR0.WP would not clear)\n");
			return;
		}
	}
	memcpy(site, kq_replace, sizeof kq_replace);
	memset(site + sizeof kq_replace, 0x90, KQ_WRITE - sizeof kq_replace);
	if (cr0 & KF_CR0_WP) {
		set_cr0(get_cr0() | KF_CR0_WP);
		if (!(get_cr0() & KF_CR0_WP))
			panic(KF_LOG "CR0.WP would not set again after writing kernel text");
	}
	ml_set_interrupts_enabled(intr);

	kq_hex(hex, site);
	printf(KF_LOG "kqueue_scan_restart: after: %s\n", hex);
	if (!kq_is_replaced(site)) {
		printf(KF_LOG "kqueue_scan_restart: refused (the write did not take)\n");
		return;
	}
	kf_kqueue_scan_restart_state = KF_APPLIED;
	printf(KF_LOG "kqueue_scan_restart: applied\n");
}
