/* spec: README.md "The kernel-fixes kext" -- debug.recaulk_kfix.<fix> reports each fix: 0 not applied,
   1 applied by this kext, 2 already in the kernel when it looked (another kext applied it) */
#include <sys/types.h>
#include <sys/sysctl.h>
#include "kfix.h"

SYSCTL_DECL(_debug);
SYSCTL_NODE(_debug, OID_AUTO, recaulk_kfix, CTLFLAG_RW | CTLFLAG_LOCKED, 0, "RecaulkKernelFixes.kext");
SYSCTL_INT(_debug_recaulk_kfix, OID_AUTO, kqueue_scan_restart, CTLFLAG_RD | CTLFLAG_LOCKED,
    &kf_kqueue_scan_restart_state, 0, "0 not applied, 1 applied, 2 applied by another kext");
SYSCTL_INT(_debug_recaulk_kfix, OID_AUTO, wait_result_prepost, CTLFLAG_RD | CTLFLAG_LOCKED,
    &kf_wait_result_prepost_state, 0, "0 not applied, 1 applied");
SYSCTL_INT(_debug_recaulk_kfix, OID_AUTO, signal_target_exit, CTLFLAG_RD | CTLFLAG_LOCKED,
    &kf_signal_target_exit_state, 0, "0 not applied, 1 applied");

int
kf_sysctl_start(void)
{
	sysctl_register_oid(&sysctl__debug_recaulk_kfix);
	sysctl_register_oid(&sysctl__debug_recaulk_kfix_kqueue_scan_restart);
	sysctl_register_oid(&sysctl__debug_recaulk_kfix_wait_result_prepost);
	sysctl_register_oid(&sysctl__debug_recaulk_kfix_signal_target_exit);
	return 0;
}

void
kf_sysctl_stop(void)
{
	sysctl_unregister_oid(&sysctl__debug_recaulk_kfix_signal_target_exit);
	sysctl_unregister_oid(&sysctl__debug_recaulk_kfix_wait_result_prepost);
	sysctl_unregister_oid(&sysctl__debug_recaulk_kfix_kqueue_scan_restart);
	sysctl_unregister_oid(&sysctl__debug_recaulk_kfix);
}
