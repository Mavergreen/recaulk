/* spec: README.md "The kernel-fixes kext" -- what kmod.c and the fixes share; all of it stays private */
#ifndef RECAULK_KFIX_H
#define RECAULK_KFIX_H
#define KF_LOG "RecaulkKernelFixes: "
/* the state each fix's sysctl reports */
enum kf_state { KF_NOT_APPLIED = 0, KF_APPLIED = 1, KF_FOREIGN = 2 };
extern int kf_kqueue_scan_restart_state;
void kf_kqueue_scan_restart_apply(void);
int kf_sysctl_start(void);
void kf_sysctl_stop(void);
#endif
