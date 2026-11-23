/* spec: README.md "The kernel-fixes kext" -- the kext's identity, start and stop: it starts only on Darwin 13
   (10.9), applies its fixes, and refuses to stop once any fix is in the kernel, whose patched code would
   otherwise jump into an unloaded kext or lose its fix */
#include <mach/mach_types.h>
#include <mach/kmod.h>
#include <libkern/version.h>
#include "core.h"
#include "kfix.h"

extern int printf(const char *, ...);

#ifndef RECAULK_KPI_VERSION
#error "build/build-kext.sh defines RECAULK_KPI_VERSION, the bundle's CFBundleVersion"
#endif

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
	if (kf_sysctl_start() != 0) {
		printf(KF_LOG "not starting: cannot register its sysctls\n");
		return KERN_FAILURE;
	}
	printf(KF_LOG "started " RECAULK_KPI_VERSION "\n");
	kf_apply_all();
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
	kf_sysctl_stop();
	return KERN_SUCCESS;
}

/* platform: libkmod.a's _start and _stop call _realmain and _antimain; kxld finds _kmod_info by name */
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(dev.mavergreen.recaulk.kernelfixes, RECAULK_KPI_VERSION, _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = kf_start;
__private_extern__ kmod_stop_func_t *_antimain = kf_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
