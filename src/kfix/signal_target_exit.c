/* spec: README.md "The kernel-fixes kext" -- signal_target_exit: 10.9's psignal_internal picks a target thread
   (get_signalthread, check_actforsig in osfmk/kern/bsd_kern.c) without taking a reference, then calls
   thread_abort_safely on it (xnu-2422.115.4 bsd/kern/kern_sig.c:2164), all while holding the target process's
   P_LINSIGNAL (kern_sig.c:1774-1802 to 2167). If that thread exits and is freed in between, thread_abort_safely
   locks a destroyed mutex: panic "trying to interlock destroyed mutex". The fix makes an exiting thread, before its
   uthread is torn down, wait out any psignal in flight on its process: proc_signalstart then proc_signalend. It
   hooks the one call to uthread_cleanup in thread_terminate_self (thread->active is already clear there, so no
   later psignal picks it), not uthread_cleanup's entry, which thread_create_internal's failure paths reach during
   fork while holding the child's P_LINSIGNAL (osfmk/kern/thread.c:730, 766). kernel_task's threads skip it. */
#include <sys/types.h>
#include <sys/errno.h>
#include <string.h>
#include "kfix.h"

extern int printf(const char *, ...);

/* platform: 10.9.5 13F1911, otool -tV: _thread_terminate_self+0xf1 is
     48 8b 93 f0 02 00 00   movq 0x2f0(%rbx), %rdx   (task->bsd_info, the proc)
     48 89 df               movq %rbx, %rdi          (the task)
     e8 xx xx xx xx         callq _uthread_cleanup    (rsi, the uthread, loaded at +0xe0)
   the only call to _uthread_cleanup before _thread_sched_call */
static const uint8_t ste_before[10] = { 0x48, 0x8b, 0x93, 0xf0, 0x02, 0x00, 0x00, 0x48, 0x89, 0xdf };

typedef void (*kf_cleanup_fn)(void *task, void *uthread, void *proc);
static kf_cleanup_fn ste_real_cleanup;
static void (*ste_signalstart)(void *proc, int locked);
static void (*ste_signalend)(void *proc, int locked);
static void *const *ste_kernproc;

/* uthread_cleanup's replacement at the hooked call: the barrier, then the kernel's own */
static void
kf_signal_handler(void *task, void *uthread, void *proc)
{
	if (proc != NULL && proc != *ste_kernproc) {
		ste_signalstart(proc, 0);
		ste_signalend(proc, 0);
	}
	ste_real_cleanup(task, uthread, proc);
}

const char *const kf_ste_syms[KF_STE_NSYMS] = {
	"_thread_terminate_self", "_thread_sched_call", "_uthread_cleanup", "_timer_call_init",
	"_proc_signalstart", "_proc_signalend", "_kernproc",
};
enum { S_FN, S_FN_END, S_CLEANUP, S_GAP_FN, S_START, S_END, S_KERNPROC };

int kf_signal_target_exit_state = KF_NOT_APPLIED;

int
kf_signal_target_exit_apply(const uint64_t *v, const int *found, uint64_t slide, const struct rk_kernel *k,
    const char **why)
{
	for (int i = 0; i < KF_STE_NSYMS; i++) {
		if (!found[i]) {
			*why = "a symbol it needs is not in /mach_kernel";
			return ESRCH;
		}
	}
	for (int i = 0; i < KF_STE_NSYMS; i++) {
		if (i == S_KERNPROC)
			continue;
		if (v[i] < k->text_vmaddr || v[i] - k->text_vmaddr >= k->text_vmsize) {
			*why = "a function it needs lies outside the kernel's __TEXT";
			return ESRCH;
		}
	}
	if (v[S_FN_END] <= v[S_FN] || v[S_FN_END] - v[S_FN] > 4096 || v[S_GAP_FN] < k->text_vmaddr + 15) {
		*why = "thread_terminate_self's extent or the padding's place is not believable";
		return ESRCH;
	}
	uint64_t fn = v[S_FN] + slide, call;
	int err = kf_find_call((const uint8_t *)(uintptr_t)fn, (size_t)(v[S_FN_END] - v[S_FN]), fn, v[S_CLEANUP] + slide,
	    ste_before, sizeof ste_before, &call, why);
	if (err != 0)
		return err;
	/* the trampoline: the padding before timer_call_init, after the previous function's ret */
	uint8_t *gap = (uint8_t *)(uintptr_t)(v[S_GAP_FN] + slide - KF_TRAMPOLINE_LEN);
	if (!kf_gap_ok(gap - 1, KF_TRAMPOLINE_LEN)) {
		*why = "the padding before timer_call_init is not a ret and 14 NOPs";
		return ESRCH;
	}
	int32_t disp;
	if ((err = kf_rel32(call + 5, (uint64_t)(uintptr_t)gap, &disp)) != 0) {
		*why = "the padding is out of the call's reach";
		return err;
	}
	if (!kf_store_ok(call + 1, 4)) {
		*why = "the call's displacement straddles a cache line";
		return ESRCH;
	}
	ste_real_cleanup = (kf_cleanup_fn)(uintptr_t)(v[S_CLEANUP] + slide);
	ste_signalstart = (void (*)(void *, int))(uintptr_t)(v[S_START] + slide);
	ste_signalend = (void (*)(void *, int))(uintptr_t)(v[S_END] + slide);
	ste_kernproc = (void *const *)(uintptr_t)(v[S_KERNPROC] + slide);
	uint8_t tr[KF_TRAMPOLINE_LEN];
	kf_trampoline(tr, (uint64_t)(uintptr_t)&kf_signal_handler);
	if (kf_write_text(gap, tr, sizeof tr) != 0) {
		*why = "the trampoline write did not take";
		return EIO;
	}
	if (kf_write_text((void *)(uintptr_t)(call + 1), &disp, sizeof disp) != 0) {
		*why = "the call's displacement write did not take (the trampoline stays, unreached)";
		return EIO;
	}
	return 0;
}
