/* spec: README.md "The kernel-fixes kext" -- kernel text is written with every CPU parked: mp_rendezvous_no_intrs
   (com.apple.kpi.unsupported) runs the action on each CPU with interrupts off and returns only once every CPU has
   finished it (xnu-2422.115.4 osfmk/i386/mp.c, mp_rendezvous: entry, action and exit barriers). The first CPU in
   writes, with its CR0.WP cleared and restored, each step checked; the rest wait at the exit barrier, so no CPU
   runs the bytes while they change. */
#include <sys/types.h>
#include <sys/errno.h>
#include <string.h>
#include <mach/mach_types.h>
#include <i386/proc_reg.h>
#include <kern/debug.h>
#include "kfix.h"

extern void mp_rendezvous_no_intrs(void (*action)(void *), void *arg);

#define KF_CR0_WP 0x00010000UL

struct kf_write {
	void *dst;
	const void *src;
	size_t len;
	int claimed;
	int err;
};

static void
kf_write_action(void *arg)
{
	struct kf_write *w = arg;
	if (__atomic_exchange_n(&w->claimed, 1, __ATOMIC_ACQ_REL) != 0)
		return;
	uintptr_t cr0 = get_cr0();
	if (!(cr0 & KF_CR0_WP)) {
		w->err = EIO;	/* the kernel runs with WP set; anything else is not the kernel this was written for */
		return;
	}
	set_cr0(cr0 & ~KF_CR0_WP);
	if (get_cr0() & KF_CR0_WP) {
		w->err = EIO;
		return;
	}
	memcpy(w->dst, w->src, w->len);
	set_cr0(get_cr0() | KF_CR0_WP);
	if (!(get_cr0() & KF_CR0_WP))
		panic(KF_LOG "CR0.WP would not set again after writing kernel text");
	w->err = memcmp(w->dst, w->src, w->len) == 0 ? 0 : EIO;
}

int
kf_write_text(void *dst, const void *src, size_t len)
{
	struct kf_write w = { dst, src, len, 0, EIO };
	mp_rendezvous_no_intrs(kf_write_action, &w);
	return w.err;
}
