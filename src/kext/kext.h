/* spec: README.md "The kernel back-fill kext" -- what kmod.c and notify.c share; all of it stays private */
#ifndef RECAULK_KPI_KEXT_H
#define RECAULK_KPI_KEXT_H
#define RK_LOG "RecaulkKPI: "
int rk_notify_start(void);
void rk_notify_stop(void);
#endif
