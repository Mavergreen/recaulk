/* spec: .superpowers/plans/2026-11-23-kernel-fixes-kext.md -- TEST ONLY, never shipped: widens the race
   signal_target_exit fixes, so a stress can hit it in minutes instead of days. psignal_internal picks a target
   thread without a reference and later calls thread_abort_safely on it (xnu-2422.115.4 bsd/kern/kern_sig.c:2164);
   this retargets that one call, through a trampoline in kernel padding, to a handler that waits first, so a picked
   thread that is exiting is freed before the abort. Without RecaulkKernelFixes: expect "trying to interlock
   destroyed mutex". With it: the exiting thread waits out the psignal in flight, so no panic.
   platform: 10.9.5 13F1911 only (UUID checked); the 2026-11-23 11:33 panic's backtrace returns to
   _threadsignal+0x9db, the call below. It cannot unload once applied. */
#include <sys/types.h>
#include <sys/errno.h>
#include <string.h>
#include <mach/mach_types.h>
#include <mach/kmod.h>
#include <kern/debug.h>
#include <sys/sysctl.h>
#include "../../../src/kfix/kfix.h"
#include "kresolve.h"

extern int printf(const char *, ...);
extern void delay(int usec);

#define W_LOG "RecaulkKfixWiden: "
#define W_DELAY_USEC 5000
/* every signal sender waits this long, and the kext cannot unload: a larger value would need a reboot */
#define W_DELAY_MAX_USEC 100000

/* platform: 10.9.5 13F1911, otool -tV _threadsignal (psignal_internal is inlined behind it):
     48 8b 7d c8      movq -0x38(%rbp), %rdi   (sig_thread)
     e8 xx xx xx xx   callq _thread_abort_safely   at 0xffffff80005e2506, the only call to it there */
static const uint8_t w_before[4] = { 0x48, 0x8b, 0x7d, 0xc8 };
static const uint8_t w_uuid[16] = KF_UUID_13F1911;

static kern_return_t (*w_real)(void *thread);
static int w_applied;

/* platform: 10.9.5 13F1911 struct thread offsets, from otool -tV: thread_abort_safely locks the thread's mutex at
   +0x368 and tests active at +0x37c bit 0; thread_tid returns +0x3f8. A destroyed lck_mtx carries
   LCK_MTX_TAG_DESTROYED (0x07fe2007) in its tag word at +8 (xnu-2422.115.4 osfmk/i386/locks.h). */
#define W_MUTEX 0x368
#define W_ACTIVE 0x37c
#define W_TID 0x3f8
#define W_TAG_DESTROYED 0x07fe2007u

/* debug.kfixwiden: mode 0 (default) classifies each delayed abort and SKIPS the abort when its target is no longer
   the picked thread, so nothing panics; mode 1 calls through always (the real panic). Counters, by the target's
   state after the delay: live (same thread, active), exiting (same thread, inactive, mutex intact), reused (another
   thread now: thread id changed), destroyed (mutex destroyed: the 11:33 panic). */
static int w_mode, w_delay_us = W_DELAY_USEC;
static int w_picks, w_live, w_exiting, w_reused, w_destroyed;

static kern_return_t
w_handler(void *thread)
{
	const char *t = thread;
	uint64_t tid = *(volatile const uint64_t *)(t + W_TID);
	__atomic_add_fetch(&w_picks, 1, __ATOMIC_RELAXED);
	if (w_delay_us > 0)
		delay(w_delay_us);
	uint32_t tag = *(volatile const uint32_t *)(t + W_MUTEX + 8);
	int gone = 0;
	if (tag == W_TAG_DESTROYED) {
		__atomic_add_fetch(&w_destroyed, 1, __ATOMIC_RELAXED);
		gone = 1;
	} else if (*(volatile const uint64_t *)(t + W_TID) != tid) {
		__atomic_add_fetch(&w_reused, 1, __ATOMIC_RELAXED);
		gone = 1;
	} else if ((*(volatile const uint8_t *)(t + W_ACTIVE) & 1) == 0) {
		__atomic_add_fetch(&w_exiting, 1, __ATOMIC_RELAXED);
	} else {
		__atomic_add_fetch(&w_live, 1, __ATOMIC_RELAXED);
	}
	if (gone && w_mode == 0)
		return KERN_TERMINATED;
	return w_real(thread);
}

SYSCTL_DECL(_debug);
SYSCTL_NODE(_debug, OID_AUTO, kfixwiden, CTLFLAG_RW | CTLFLAG_LOCKED, 0, "RecaulkKfixWiden (test only)");
SYSCTL_INT(_debug_kfixwiden, OID_AUTO, mode, CTLFLAG_RW | CTLFLAG_LOCKED, &w_mode, 0, "0 classify and skip, 1 call through");
static int
w_delay_sysctl(struct sysctl_oid *oidp, void *arg1, int arg2, struct sysctl_req *req)
{
	(void)arg1;
	(void)arg2;
	int v = w_delay_us;
	int err = sysctl_handle_int(oidp, &v, 0, req);
	if (err != 0 || req->newptr == USER_ADDR_NULL)
		return err;
	if (v < 0 || v > W_DELAY_MAX_USEC)
		return EINVAL;
	w_delay_us = v;
	return 0;
}
SYSCTL_PROC(_debug_kfixwiden, OID_AUTO, delay_us, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, 0, 0, w_delay_sysctl, "I",
    "delay before the abort, 0 to 100000 us");
SYSCTL_INT(_debug_kfixwiden, OID_AUTO, picks, CTLFLAG_RW | CTLFLAG_LOCKED, &w_picks, 0, "");
SYSCTL_INT(_debug_kfixwiden, OID_AUTO, live, CTLFLAG_RW | CTLFLAG_LOCKED, &w_live, 0, "");
SYSCTL_INT(_debug_kfixwiden, OID_AUTO, exiting, CTLFLAG_RW | CTLFLAG_LOCKED, &w_exiting, 0, "");
SYSCTL_INT(_debug_kfixwiden, OID_AUTO, reused, CTLFLAG_RW | CTLFLAG_LOCKED, &w_reused, 0, "");
SYSCTL_INT(_debug_kfixwiden, OID_AUTO, destroyed, CTLFLAG_RW | CTLFLAG_LOCKED, &w_destroyed, 0, "");

static void
w_apply(void)
{
	struct rk_sym want[6] = {
		{ "_threadsignal", 0, 0 }, { "_psignal_locked", 0, 0 }, { "_thread_abort_safely", 0, 0 },
		{ "_btlog_create", 0, 0 }, { "_printf", 0, 0 }, { "_panic", 0, 0 },
	};
	uint64_t live[6] = { 0, 0, 0, 0, (uint64_t)(uintptr_t)&printf, (uint64_t)(uintptr_t)&panic };
	struct rk_kernel k;
	uint64_t slide, call;
	const char *why = "";
	int err;
	if ((err = rk_resolve_live(want, live, 6, &k, &slide, &why)) != 0) {
		printf(W_LOG "not applied: %s (%d)\n", why, err);
		return;
	}
	if (!kf_uuid_eq(k.uuid, w_uuid)) {
		printf(W_LOG "not applied: not 13F1911\n");
		return;
	}
	for (int i = 0; i < 4; i++)
		if (!want[i].found) {
			printf(W_LOG "not applied: %s missing\n", want[i].name);
			return;
		}
	uint64_t fn = want[0].value + slide;
	if ((err = kf_find_call((const uint8_t *)(uintptr_t)fn, (size_t)(want[1].value - want[0].value), fn,
	    want[2].value + slide, w_before, sizeof w_before, &call, &why)) != 0) {
		printf(W_LOG "not applied: %s\n", why);
		return;
	}
	uint8_t *gap = (uint8_t *)(uintptr_t)(want[3].value + slide - KF_TRAMPOLINE_LEN);
	int32_t disp;
	uint8_t tr[KF_TRAMPOLINE_LEN];
	if (!kf_gap_ok(gap - 1, KF_TRAMPOLINE_LEN) || kf_rel32(call + 5, (uint64_t)(uintptr_t)gap, &disp) != 0 ||
	    !kf_store_ok(call + 1, 4)) {
		printf(W_LOG "not applied: the padding before btlog_create or the call is not as expected\n");
		return;
	}
	w_real = (kern_return_t (*)(void *))(uintptr_t)(want[2].value + slide);
	kf_trampoline(tr, (uint64_t)(uintptr_t)&w_handler);
	if (!kf_trampoline_fbt_safe(tr, gap[KF_TRAMPOLINE_LEN])) {
		printf(W_LOG "not applied: this load's handler address could be taken by DTrace's fbt for a return site\n");
		return;
	}
	if (kf_write_text(gap, tr, sizeof tr) != 0 || kf_write_text((void *)(uintptr_t)(call + 1), &disp, 4) != 0) {
		printf(W_LOG "not applied: write failed\n");
		return;
	}
	w_applied = 1;
	sysctl_register_oid(&sysctl__debug_kfixwiden);
	sysctl_register_oid(&sysctl__debug_kfixwiden_mode);
	sysctl_register_oid(&sysctl__debug_kfixwiden_delay_us);
	sysctl_register_oid(&sysctl__debug_kfixwiden_picks);
	sysctl_register_oid(&sysctl__debug_kfixwiden_live);
	sysctl_register_oid(&sysctl__debug_kfixwiden_exiting);
	sysctl_register_oid(&sysctl__debug_kfixwiden_reused);
	sysctl_register_oid(&sysctl__debug_kfixwiden_destroyed);
	printf(W_LOG "applied: psignal waits %d us before thread_abort_safely (call at 0x%llx)\n", W_DELAY_USEC,
	    (unsigned long long)(call - slide));
}

kern_return_t w_start(kmod_info_t *ki, void *d);
kern_return_t w_stop(kmod_info_t *ki, void *d);

kern_return_t
w_start(kmod_info_t *ki, void *d)
{
	(void)ki; (void)d;
	w_apply();
	return KERN_SUCCESS;
}

kern_return_t
w_stop(kmod_info_t *ki, void *d)
{
	(void)ki; (void)d;
	return w_applied ? KERN_FAILURE : KERN_SUCCESS;
}

/* platform: libkmod.a's _start and _stop call _realmain and _antimain; kxld finds _kmod_info by name */
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(dev.mavergreen.recaulk.kfixwiden, "1.0.0", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = w_start;
__private_extern__ kmod_stop_func_t *_antimain = w_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
