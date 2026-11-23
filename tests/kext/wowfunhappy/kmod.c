/* spec: README.md "The kernel-fixes kext" -- the kmod glue Xcode generates for KQueueScanContinuePatch, which
   tests/kfix-runtime-test.sh builds unchanged from Wowfunhappy's gist (KQueueScanContinuePatch.c here, CC-0:
   https://gist.github.com/Wowfunhappy/8212f5bea4c601ac9a6297789f232321, comment 6488041) for its foreign round */
#include <mach/mach_types.h>
#include <mach/kmod.h>
extern kern_return_t KQueueScanContinuePatch_start(kmod_info_t *, void *);
extern kern_return_t KQueueScanContinuePatch_stop(kmod_info_t *, void *);
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(wowfunhappy.KQueueScanContinuePatch, "1.0", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = KQueueScanContinuePatch_start;
__private_extern__ kmod_stop_func_t *_antimain = KQueueScanContinuePatch_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
