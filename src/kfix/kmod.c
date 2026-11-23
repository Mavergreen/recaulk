/* spec: README.md "The kernel-fixes kext" -- the kext's identity, start and stop: it starts only on Darwin 13
   (10.9), applies its fixes, and refuses to stop once any fix is in the kernel, whose patched code would
   otherwise jump into an unloaded kext or lose its fix */
#include <mach/mach_types.h>
#include <mach/kmod.h>
#include <libkern/version.h>
#include <kern/locks.h>
#include <kern/sched_prim.h>
#include <kern/thread.h>
#include <kern/clock.h>

/* platform: com.apple.kpi.unsupported exports delay (xnu-2422.115.4 osfmk/kern/clock.h, KERNEL_PRIVATE there) */
extern void delay(int usec);
#include <sys/types.h>
#include <sys/vnode.h>
#include "core.h"
#include "kfix.h"

extern int printf(const char *, ...);

#ifndef RECAULK_KPI_VERSION
#error "build/build-kext.sh defines RECAULK_KPI_VERSION, the bundle's CFBundleVersion"
#endif

/* spec: README.md "The kernel-fixes kext" -- the fixes resolve /mach_kernel on a kernel thread of their own, so the
   kernel's credentials and the real root open it, never kextd's view; start waits for that thread */
static lck_grp_t *kf_grp;
static lck_mtx_t *kf_lock;
static int kf_done;

static void
kf_apply_thread(void *arg, wait_result_t wr)
{
	(void)arg;
	(void)wr;
	kf_apply_all();
	lck_mtx_lock(kf_lock);
	kf_done = 1;
	thread_wakeup((event_t)&kf_done);
	lck_mtx_unlock(kf_lock);
}

static void
kf_apply_on_thread(void)
{
	thread_t t;
	vnode_t root = vfs_rootvnode();
	if (root == NULLVP) {
		printf(KF_LOG "no fixes: the root filesystem is not mounted yet (load it from its LaunchDaemon)\n");
		return;
	}
	vnode_put(root);
	kf_done = 0;
	if (kernel_thread_start(kf_apply_thread, NULL, &t) != KERN_SUCCESS) {
		printf(KF_LOG "no fixes: cannot start the thread that applies them\n");
		return;
	}
	thread_deallocate(t);
	lck_mtx_lock(kf_lock);
	while (!kf_done)
		lck_mtx_sleep(kf_lock, LCK_SLEEP_DEFAULT, (event_t)&kf_done, THREAD_UNINT);
	lck_mtx_unlock(kf_lock);
}

static kern_return_t
kf_start(kmod_info_t *ki, void *data)
{
	(void)ki;
	(void)data;
	if (!rk_kernel_supported(version_major)) {
		printf(KF_LOG "not starting: this kernel is Darwin %d, and RecaulkKernelFixes fixes Darwin 13 (10.9) only\n",
		    version_major);
		return KERN_FAILURE;
	}
	if ((kf_grp = lck_grp_alloc_init("RecaulkKernelFixes", LCK_GRP_ATTR_NULL)) == NULL ||
	    (kf_lock = lck_mtx_alloc_init(kf_grp, LCK_ATTR_NULL)) == NULL) {
		printf(KF_LOG "not starting: cannot allocate its lock\n");
		if (kf_grp != NULL)
			lck_grp_free(kf_grp);
		return KERN_FAILURE;
	}
	if (kf_sysctl_start() != 0) {
		printf(KF_LOG "not starting: cannot register its sysctls\n");
		return KERN_FAILURE;
	}
	printf(KF_LOG "started " RECAULK_KPI_VERSION "\n");
	kf_apply_on_thread();
	return KERN_SUCCESS;
}

static kern_return_t
kf_stop(kmod_info_t *ki, void *data)
{
	(void)ki;
	(void)data;
	if (kf_any_applied()) {
		printf(KF_LOG "not stopping: a fix is in the kernel; it goes at reboot\n");
		return KERN_FAILURE;
	}
	/* final review #1: the apply thread wakes start while it still runs this kext's code (the unlock, its return);
	   give it time to leave before the kext's memory goes */
	delay(100 * 1000);
	kf_sysctl_stop();
	lck_mtx_free(kf_lock, kf_grp);
	lck_grp_free(kf_grp);
	return KERN_SUCCESS;
}

/* platform: libkmod.a's _start and _stop call _realmain and _antimain; kxld finds _kmod_info by name */
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(dev.mavergreen.recaulk.kernelfixes, RECAULK_KPI_VERSION, _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = kf_start;
__private_extern__ kmod_stop_func_t *_antimain = kf_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
