/* spec: README.md "The kernel-fixes kext" -- kqueue_scan_restart: when a kevent wait ends THREAD_RESTART,
   10.9's kqueue_scan_continue panics "invalid wait_result (3)" (xnu-2422.115.4 bsd/kern/kern_event.c,
   kqueue_scan_continue); newer xnu returns EBADF, and so does this.

   From KQueueScanContinuePatch, by Wowfunhappy with assistance from krackers,
   https://gist.github.com/Wowfunhappy/8212f5bea4c601ac9a6297789f232321, which Wowfunhappy declared CC-0
   (that gist, comment 6488041): its 10.9.5 13F1911 site, bytes and replacement. */
#include "kfix.h"

/* platform: 10.9.5 13F1911 (xnu-2422.115.15), at _kqueue_scan+0x8dc (the gist's 0xffffff80005c7a9c; otool -tV
   shows kqueue_scan_continue's panic there, kern_event.c:2167, before _kqueue_stat at +0x920), from the gist: the panic call's argument set-up,
   the call, and the `xor r12d, r12d` after it, which the write replaces; the last 3 bytes stay, a check of the
   far edge */
static const uint8_t kq_expect[30] = {
	0x48, 0x8d, 0x3d, 0xbb, 0xf3, 0x19, 0x00, /* lea rdi, [aSInvalidWaitre] */
	0x48, 0x8d, 0x35, 0x11, 0xf4, 0x19, 0x00, /* lea rsi, [aKqueuescancont] */
	0x44, 0x89, 0xfa,                         /* mov edx, r15d */
	0x30, 0xc0,                               /* xor al, al */
	0xe8, 0xbc, 0xb5, 0xc5, 0xff,             /* call _panic */
	0x45, 0x31, 0xe4,                         /* xor r12d, r12d */
	0x49, 0x8b, 0xb5,
};
/* mov r12d, 9 (EBADF, the error kqueue_scan_continue returns), NOPs, then the same 3 bytes */
static const uint8_t kq_replace[30] = {
	0x41, 0xbc, 0x09, 0x00, 0x00, 0x00, 0x90,
	0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
	0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
	0x49, 0x8b, 0xb5,
};

const struct kf_patch kf_kqueue_scan_restart = {
	"kqueue_scan_restart", KF_UUID_13F1911, "_kqueue_scan", 0x8dc, kq_expect, kq_replace, sizeof kq_expect,
};
