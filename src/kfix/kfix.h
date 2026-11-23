/* spec: README.md "The kernel-fixes kext" -- what kmod.c and the fixes share; all of it stays private */
#ifndef RECAULK_KFIX_H
#define RECAULK_KFIX_H
#define KF_LOG "RecaulkKernelFixes: "
#include "engine.h"
/* platform: 10.9.5 13F1911's kernel (xnu-2422.115.15): LC_UUID 8926E512-6714-34FC-B27C-6AE90EB51D5E */
#define KF_UUID_13F1911 { 0x89, 0x26, 0xe5, 0x12, 0x67, 0x14, 0x34, 0xfc, 0xb2, 0x7c, 0x6a, 0xe9, 0x0e, 0xb5, 0x1d, 0x5e }
extern const struct kf_patch kf_kqueue_scan_restart;
extern int kf_kqueue_scan_restart_state;
#include "core.h"
#define KF_STE_NSYMS 7
extern const char *const kf_ste_syms[KF_STE_NSYMS];
extern int kf_signal_target_exit_state;
/* v[i], found[i]: kf_ste_syms[i]'s unslid value from /mach_kernel */
int kf_signal_target_exit_apply(const uint64_t *v, const int *found, uint64_t slide, const struct rk_kernel *k,
    const char **why);
void kf_apply_all(void);
int kf_any_applied(void);
/* writes len bytes of kernel text with every CPU parked; 0, or EIO with nothing known written */
int kf_write_text(void *dst, const void *src, size_t len);
int kf_sysctl_start(void);
void kf_sysctl_stop(void);
#endif
