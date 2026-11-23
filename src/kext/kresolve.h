/* spec: README.md "The kernel back-fill kext" -- the live-kernel resolver RecaulkKPI and RecaulkKernelFixes share */
#ifndef RECAULK_KPI_KRESOLVE_H
#define RECAULK_KPI_KRESOLVE_H
#include "core.h"
#ifndef RECAULK_KPI_KERNEL_PATH
#define RECAULK_KPI_KERNEL_PATH "/mach_kernel"
#endif
/* Reads RECAULK_KPI_KERNEL_PATH for want[], agrees their slide with live[] (0 entries unchecked), checks those lie
   in its __TEXT, and matches the running kernel's UUID to the file's. 0, or an errno with *why set. Thread context
   only: it blocks on I/O, with the calling thread's credentials. */
int rk_resolve_live(struct rk_sym *want, const uint64_t *live, unsigned nwant, struct rk_kernel *k, uint64_t *slide,
    const char **why);
#endif
