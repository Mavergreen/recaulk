/* spec: README.md "The kernel-fixes kext" -- wait_result_prepost: 10.9's wait_queue_assert_wait64_locked returns
   THREAD_AWAKENED for a preposted wait queue set without storing it in thread->wait_result (xnu-2422.115.4
   osfmk/kern/wait_queue.c:1198-1199). kqueue_scan ignores that return and blocks; thread_block, finding the thread
   still runnable, runs kqueue_scan_continue with the wait_result the thread's previous wait left: THREAD_RESTART
   panics "invalid wait_result (3)", THREAD_TIMED_OUT ends an untimed kevent with 0 events, THREAD_INTERRUPTED with
   EINTR. xnu-2782.1.97 (10.10) stores it: `return (thread->wait_result = THREAD_AWAKENED);`, and so does this.

   Found by Wowfunhappy and krackers, with an analysis by GPT they shared (gist
   8212f5bea4c601ac9a6297789f232321, comment 6490893), checked against the source and 13F1911's binary. */
#include "kfix.h"

/* platform: 10.9.5 13F1911 (xnu-2422.115.15) -- wait_queue_assert_wait64_locked has no symbol of its own; it is
   0xffffff800024eaa0, inside _wait_queue_set_unlink_one's (0xffffff800024e9a0). The site, +0x13e, is its
   preposted test (rbx the wait queue, r14 the event, r15 the thread) through the jne to the epilogue at +0x21d.
   Nothing branches into the site but to its first byte (+0x12e's je); every slow-path branch leaves it at its end. */
static const uint8_t wr_expect[43] = {
	0x4d, 0x85, 0xf6,                         /* test r14, r14 (event == NO_EVENT64) */
	0x75, 0x26,                               /* jne end */
	0x48, 0x8b, 0x03,                         /* mov rax, [rbx] */
	0x48, 0x89, 0xc1,                         /* mov rcx, rax */
	0x48, 0x83, 0xe1, 0x03,                   /* and rcx, 3 */
	0x48, 0x83, 0xf9, 0x03,                   /* cmp rcx, 3 (wq_type == _WAIT_QUEUE_SET_inited) */
	0x75, 0x16,                               /* jne end */
	0x48, 0x83, 0xe0, 0x08,                   /* and rax, 8 (wqs_prepost) */
	0x74, 0x10,                               /* je end */
	0x48, 0x8d, 0x4b, 0x30,                   /* lea rcx, [rbx+0x30] */
	0x31, 0xc0,                               /* xor eax, eax (THREAD_AWAKENED) */
	0x48, 0x3b, 0x4b, 0x30,                   /* cmp rcx, [rbx+0x30] (wqs_preposts not empty) */
	0x0f, 0x85, 0xb4, 0x00, 0x00, 0x00,       /* jne epilogue */
};
/* the same tests, the type and prepost bits in one ((w & 0xb) == 0xb), so there is room to store eax in
   thread->wait_result before the jump. +0x58 is where thread_mark_wait_locked (unnamed, _thread_setrun+0x770)
   stores THREAD_WAITING and THREAD_INTERRUPTED, and where the wait_queue_assert_wait_with_leeway wrapper stores
   THREAD_RESTART for an invalid queue. */
static const uint8_t wr_replace[43] = {
	0x4d, 0x85, 0xf6,                         /* test r14, r14 */
	0x75, 0x26,                               /* jne end */
	0x48, 0x8b, 0x03,                         /* mov rax, [rbx] */
	0x83, 0xe0, 0x0b,                         /* and eax, 0xb */
	0x83, 0xf8, 0x0b,                         /* cmp eax, 0xb */
	0x75, 0x1b,                               /* jne end */
	0x48, 0x8d, 0x4b, 0x30,                   /* lea rcx, [rbx+0x30] */
	0x48, 0x3b, 0x4b, 0x30,                   /* cmp rcx, [rbx+0x30] */
	0x74, 0x11,                               /* je end */
	0x31, 0xc0,                               /* xor eax, eax */
	0x41, 0x89, 0x47, 0x58,                   /* mov [r15+0x58], eax */
	0xe9, 0xba, 0x00, 0x00, 0x00,             /* jmp epilogue */
	0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
};

const struct kf_patch kf_wait_result_prepost = {
	"wait_result_prepost", KF_UUID_13F1911, "_wait_queue_set_unlink_one", 0x13e, wr_expect, wr_replace,
	sizeof wr_expect, 0, /* no other kext's replacement */
};
