/* spec: README.md "The kernel-fixes kext" -- what kmod.c and the fixes share; all of it stays private */
#ifndef RECAULK_KFIX_H
#define RECAULK_KFIX_H
#define KF_LOG "RecaulkKernelFixes: "
#include "engine.h"
/* platform: 10.9.5 13F1911's kernel (xnu-2422.115.15): LC_UUID 8926E512-6714-34FC-B27C-6AE90EB51D5E */
#define KF_UUID_13F1911 { 0x89, 0x26, 0xe5, 0x12, 0x67, 0x14, 0x34, 0xfc, 0xb2, 0x7c, 0x6a, 0xe9, 0x0e, 0xb5, 0x1d, 0x5e }
extern const struct kf_patch kf_kqueue_scan_restart;
extern int kf_kqueue_scan_restart_state;
void kf_apply_all(void);
int kf_any_applied(void);
int kf_sysctl_start(void);
void kf_sysctl_stop(void);
#endif
