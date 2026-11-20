/* spec: README.md "The kernel back-fill kext" -- the kext's identity and its start and stop: it refuses to
   start on any kernel but Darwin 13 (10.9), where its back-fills follow the kernel's internals */
#include <mach/mach_types.h>
#include <mach/kmod.h>
#include <libkern/version.h>
#include "core.h"
#include "kext.h"

extern int printf(const char *, ...);

#ifndef RECAULK_KPI_VERSION
#error "build/build-kext.sh defines RECAULK_KPI_VERSION, the bundle's CFBundleVersion"
#endif

static kern_return_t
rk_start(kmod_info_t *ki, void *data)
{
	(void)ki;
	(void)data;
	if (!rk_kernel_supported(version_major)) {
		printf(RK_LOG "not starting: this kernel is Darwin %d, and RecaulkKPI back-fills Darwin 13 (10.9) only\n",
		    version_major);
		return KERN_FAILURE;
	}
	if (rk_notify_start() != 0) {
		printf(RK_LOG "not starting: cannot allocate its lock\n");
		return KERN_FAILURE;
	}
	printf(RK_LOG "started " RECAULK_KPI_VERSION "; vnode_notify resolves on first use\n");
	return KERN_SUCCESS;
}

static kern_return_t
rk_stop(kmod_info_t *ki, void *data)
{
	(void)ki;
	(void)data;
	rk_notify_stop();
	return KERN_SUCCESS;
}

/* platform: libkmod.a's _start and _stop call _realmain and _antimain; kxld finds _kmod_info by name */
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(dev.mavergreen.recaulk.kpi, RECAULK_KPI_VERSION, _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = rk_start;
__private_extern__ kmod_stop_func_t *_antimain = rk_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
