/* RecaulkKernelFixes' pure engine (src/kfix/engine.c) on synthetic bytes, in userspace: a patch site that holds
   the expected bytes, the replacement already, or neither; UUID comparison; and the recaulk_kfix boot-arg. */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include "../../src/kext/core.h"
#include "../../src/kfix/engine.h"
#include "../../src/kfix/kfix.h"

static int failures;
static void
ok(int cond, const char *name, const char *detail)
{
	if (cond)
		printf("ok %s\n", name);
	else {
		printf("FAIL: %s: %s\n", name, detail);
		failures++;
	}
}

static const uint8_t expect[6] = { 0xe8, 1, 2, 3, 4, 0x45 };
static const uint8_t replace[6] = { 0x41, 0xbc, 9, 0, 0, 0 };
static const struct kf_patch P = { "demo", { 0 }, NULL, 0, expect, replace, sizeof expect, NULL };
static const uint8_t other[6] = { 0x41, 0xbc, 9, 0, 0x90, 0x90 };
static const struct kf_patch PF = { "demo", { 0 }, NULL, 0, expect, replace, sizeof expect, other };

/* 1 when DTrace's fbt, scanning these bytes with the one before and the one after, could take one for a return
   site: 5d or c9 followed by c3, c2, e9, eb or ea (xnu-2422.115.4 bsd/dev/i386/fbt_x86.c, __provide_probe_64) */
static int
fbt_ret_like(uint8_t c, uint8_t d)
{
	return (c == 0x5d || c == 0xc9) && (d == 0xc3 || d == 0xc2 || d == 0xe9 || d == 0xeb || d == 0xea);
}
static int
fbt_hazard(uint8_t prev, const uint8_t *b, size_t n, uint8_t next)
{
	if (fbt_ret_like(prev, b[0]) || fbt_ret_like(b[n - 1], next))
		return 1;
	for (size_t i = 1; i < n; i++)
		if (fbt_ret_like(b[i - 1], b[i]))
			return 1;
	return 0;
}
/* the target of the rel8 branch at b[i], b at address at */
static uint64_t
rel8(uint64_t at, const uint8_t *b, size_t i)
{
	return at + i + 2 + (int64_t)(int8_t)b[i + 1];
}
/* the target of the oplen-byte rel32 branch at b[i] */
static uint64_t
rel32(uint64_t at, const uint8_t *b, size_t i, size_t oplen)
{
	int32_t d;
	memcpy(&d, b + i + oplen - 4, 4);
	return at + i + oplen + (int64_t)d;
}

/* ---- the real 13F1911 kernel file, read only: the sites the fixes pin are where they say ---- */
static int kfd;
static int fd_read(void *c, void *buf, size_t len, uint64_t off)
{
	(void)c;
	return pread(kfd, buf, len, (off_t)off) == (ssize_t)len ? 0 : EIO;
}
static void *m_alloc(size_t n) { return malloc(n); }
static void m_free(void *p, size_t n) { (void)n; free(p); }

static void
real_kernel(const char *path)
{
	static const uint8_t uuid13F1911[16] = { 0x89, 0x26, 0xe5, 0x12, 0x67, 0x14, 0x34, 0xfc, 0xb2, 0x7c, 0x6a,
		0xe9, 0x0e, 0xb5, 0x1d, 0x5e };
	static const uint8_t before[10] = { 0x48, 0x8b, 0x93, 0xf0, 0x02, 0x00, 0x00, 0x48, 0x89, 0xdf };
	struct rk_sym want[] = { { "_thread_terminate_self", 0, 0 }, { "_thread_sched_call", 0, 0 },
		{ "_uthread_cleanup", 0, 0 }, { "_timer_call_init", 0, 0 }, { "_kqueue_scan", 0, 0 },
		{ "_wait_queue_set_unlink_one", 0, 0 }, { "_printf", 0, 0 } };
	struct rk_mem mem = { m_alloc, m_free };
	struct rk_kernel k;
	struct stat sb;
	const char *why = NULL;
	if ((kfd = open(path, O_RDONLY)) < 0 || fstat(kfd, &sb) != 0) {
		ok(0, "real_kernel", "cannot open the kernel file");
		return;
	}
	struct rk_file f = { NULL, (uint64_t)sb.st_size, fd_read };
	if (rk_read_kernel(&f, &mem, &k, want, 7, &why) != 0) {
		ok(0, "real_kernel", why);
		return;
	}
	if (!kf_uuid_eq(k.uuid, uuid13F1911)) {
		printf("skip real_kernel: %s is not 13F1911's\n", path);
		return;
	}
	/* platform: the 10.9 kernel's __TEXT segment starts at file offset 0 */
	size_t fl = (size_t)(want[1].value - want[0].value);
	uint8_t *fn = malloc(fl), pre[15], kq[30];
	uint64_t call = 0;
	f.read(NULL, fn, fl, want[0].value - k.text_vmaddr);
	ok(kf_find_call(fn, fl, want[0].value, want[2].value, before, sizeof before, &call, &why) == 0
	    && call == want[0].value + 0xf1, "real_signal_site", "13F1911's call to uthread_cleanup is not at +0xf1");
	ok(kf_store_ok(call + 1, 4), "real_signal_store", "13F1911's displacement straddles a line");
	f.read(NULL, pre, sizeof pre, want[3].value - 15 - k.text_vmaddr);
	ok(kf_gap_ok(pre, 14), "real_gap", "13F1911's padding before timer_call_init is not ret + 14 NOPs");
	int32_t d;
	ok(kf_rel32(call + 5, want[3].value - 14, &d) == 0, "real_gap_reach", "the padding is out of reach");
	static const uint8_t vfc[16] = { 0xf6, 0x83, 0x23, 0x01, 0x00, 0x00, 0x02, 0x74, 0x18, 0x48, 0x8b, 0xbb, 0xf8, 0x00,
		0x00, 0x00 };
	uint8_t got[16];
	f.read(NULL, got, sizeof got, want[2].value + 0xee - k.text_vmaddr);
	ok(memcmp(got, vfc, sizeof got) == 0, "real_vfork_offsets",
	    "_uthread_cleanup+0xee is not the uu_flag/uu_proc check the vfork barrier pins");
	static const uint8_t kq_head[5] = { 0x48, 0x8d, 0x3d, 0xbb, 0xf3 };
	f.read(NULL, kq, sizeof kq, want[4].value + 0x8dc - k.text_vmaddr);
	ok(memcmp(kq, kq_head, sizeof kq_head) == 0 && kq[19] == 0xe8, "real_kqueue_site",
	    "_kqueue_scan+0x8dc does not start the panic call's set-up");

	enum kf_state st;
	const struct kf_patch *qp = &kf_kqueue_scan_restart, *wp = &kf_wait_result_prepost;
	uint64_t qat = want[4].value + qp->offset, wat = want[5].value + wp->offset;
	uint8_t qs[64], ws[64], around[2];
	ok(strcmp(qp->anchor, "_kqueue_scan") == 0 && qp->len == 30 && kf_uuid_eq(qp->uuid, uuid13F1911), "kq_table",
	    "kqueue_scan_restart's anchor, length or UUID changed");
	f.read(NULL, qs, qp->len, qat - k.text_vmaddr);
	ok(kf_check_patch(qp, qs, &st, &why) == 0 && st == KF_NOT_APPLIED, "real_kqueue_bytes",
	    "13F1911's _kqueue_scan+0x8dc does not hold kqueue_scan_restart's expected bytes");
	/* spec: README.md "The kernel-fixes kext" -- the backstop logs instead of panicking: the panic's own set-up, its
	   call retargeted to printf, then error = EBADF. r12d is 0x23 on the one path in (_kqueue_scan+0x851), so
	   mov r12b, 9 leaves it 9, and printf keeps r12 (callee-saved). */
	ok(memcmp(qp->replace, qp->expect, 19) == 0 && qp->replace[19] == 0xe8
	    && rel32(qat, qp->replace, 19, 5) == want[6].value, "kq_logs",
	    "the backstop does not call printf with the panic's own arguments");
	static const uint8_t r12b9[3] = { 0x41, 0xb4, 0x09 }, r12d23[6] = { 0x41, 0xbc, 0x23, 0, 0, 0 };
	ok(memcmp(qp->replace + 24, r12b9, 3) == 0 && memcmp(qp->replace + 27, qp->expect + 27, 3) == 0, "kq_ebadf",
	    "the backstop does not set r12b to EBADF and keep the last 3 bytes");
	uint8_t pre23[6], jne[2];
	f.read(NULL, pre23, sizeof pre23, want[4].value + 0x851 - k.text_vmaddr);
	f.read(NULL, jne, sizeof jne, want[4].value + 0x864 - k.text_vmaddr);
	ok(memcmp(pre23, r12d23, sizeof pre23) == 0 && jne[0] == 0x75 && rel8(want[4].value + 0x864, jne, 0) == qat,
	    "kq_r12_precondition", "_kqueue_scan+0x851 is not mov r12d, 0x23 before the one branch to the site");
	ok(qp->foreign != NULL && memcmp(qp->foreign, qp->expect, qp->len) != 0
	    && memcmp(qp->foreign, qp->replace, qp->len) != 0, "kq_foreign",
	    "the earlier, silent replacement (Wowfunhappy's) is not recognised as another kext's");
	f.read(NULL, around, 1, qat - 1 - k.text_vmaddr);
	f.read(NULL, around + 1, 1, qat + qp->len - k.text_vmaddr);
	ok(!fbt_hazard(around[0], qp->replace, qp->len, around[1]), "kq_fbt", "fbt could take a backstop byte for a return");

	/* spec: README.md "The kernel-fixes kext" -- wait_result_prepost: the preposted fast path of the unnamed
	   wait_queue_assert_wait64_locked (0xffffff800024eaa0, inside _wait_queue_set_unlink_one's symbol) stores
	   THREAD_AWAKENED in thread->wait_result (+0x58) before it returns it, as xnu-2782 does */
	ok(strcmp(wp->name, "wait_result_prepost") == 0 && strcmp(wp->anchor, "_wait_queue_set_unlink_one") == 0
	    && wp->offset == 0x13e && wp->len == 43 && kf_uuid_eq(wp->uuid, uuid13F1911) && wp->foreign == NULL,
	    "wr_table", "wait_result_prepost's name, anchor, offset, length or UUID is not as pinned");
	f.read(NULL, ws, wp->len, wat - k.text_vmaddr);
	ok(kf_check_patch(wp, ws, &st, &why) == 0 && st == KF_NOT_APPLIED, "real_wr_bytes",
	    "13F1911's _wait_queue_set_unlink_one+0x13e does not hold wait_result_prepost's expected bytes");
	const uint8_t *e = wp->expect, *r = wp->replace;
	uint64_t end = wat + wp->len, epi = rel32(wat, e, 0x25, 6);
	uint8_t epib[5];
	static const uint8_t epiw[5] = { 0x48, 0x83, 0xc4, 0x18, 0x5b };
	f.read(NULL, epib, sizeof epib, epi - k.text_vmaddr);
	ok(e[0x25] == 0x0f && memcmp(epib, epiw, sizeof epib) == 0, "wr_epilogue",
	    "the original fast path does not return through the epilogue");
	ok(rel8(wat, e, 3) == end && rel8(wat, e, 0x13) == end && rel8(wat, e, 0x19) == end, "wr_expect_branches",
	    "the original's slow-path branches do not all reach the end of the site");
	ok(r[3] == 0x75 && rel8(wat, r, 3) == end && r[0x0e] == 0x75 && rel8(wat, r, 0x0e) == end
	    && r[0x18] == 0x74 && rel8(wat, r, 0x18) == end, "wr_replace_branches",
	    "the replacement's slow-path branches do not all reach the end of the site");
	static const uint8_t store[6] = { 0x31, 0xc0, 0x41, 0x89, 0x47, 0x58 };
	ok(memcmp(r + 0x1a, store, sizeof store) == 0 && r[0x20] == 0xe9 && rel32(wat, r, 0x20, 5) == epi,
	    "wr_store_then_return", "the fast path does not store THREAD_AWAKENED to [r15+0x58] and jump to the epilogue");
	ok(memcmp(r, e, 6) == 0, "wr_event_test_kept", "the event == NO_EVENT64 test changed");
	f.read(NULL, around, 1, wat - 1 - k.text_vmaddr);
	f.read(NULL, around + 1, 1, end - k.text_vmaddr);
	ok(!fbt_hazard(around[0], r, wp->len, around[1]), "wr_fbt", "fbt could take a wait_result_prepost byte for a return");
	free(fn);
	close(kfd);
}

int
main(int argc, char **argv)
{
	enum kf_state st = (enum kf_state)-1;
	const char *why = NULL;
	uint8_t site[6];

	memcpy(site, expect, sizeof site);
	ok(kf_check_patch(&P, site, &st, &why) == 0 && st == KF_NOT_APPLIED, "patch_fresh", "expected bytes are not KF_NOT_APPLIED");
	memcpy(site, replace, sizeof site);
	ok(kf_check_patch(&P, site, &st, &why) == 0 && st == KF_FOREIGN, "already_applied", "replacement bytes are not KF_FOREIGN");
	memcpy(site, expect, sizeof site);
	site[3] ^= 0xff;
	why = NULL;
	ok(kf_check_patch(&P, site, &st, &why) == ESRCH && why != NULL, "patch_wrong_bytes", "a changed byte is not ESRCH with a reason");

	uint8_t a[16] = { 1, 2, 3 }, b[16] = { 1, 2, 3 };
	ok(kf_uuid_eq(a, b), "uuid_same", "equal UUIDs differ");
	b[0] ^= 1;
	ok(!kf_uuid_eq(a, b), "wrong_uuid", "different UUIDs compare equal");
	memcpy(site, other, sizeof site);
	ok(kf_check_patch(&PF, site, &st, &why) == 0 && st == KF_FOREIGN, "foreign_alternative",
	    "another kext's different replacement is not KF_FOREIGN");
	ok(kf_check_patch(&P, site, &st, &why) == ESRCH, "foreign_none", "a patch with no alternative took other bytes");
	ok(kf_bootarg_disabled("recaulk_kfix=-wait_result_prepost", "wait_result_prepost") == 1
	    && kf_bootarg_disabled("recaulk_kfix=-wait_result_prepost", "kqueue_scan_restart") == 0, "bootarg_prepost",
	    "-wait_result_prepost does not turn off exactly that fix");

	ok(kf_bootarg_disabled("-v recaulk_kfix=0", "kqueue_scan_restart") == 1, "bootarg_all_off", "recaulk_kfix=0 leaves it on");
	ok(kf_bootarg_disabled("-v recaulk_kfix=-kqueue_scan_restart debug=0x144", "kqueue_scan_restart") == 1,
	    "bootarg_named_off", "-name leaves it on");
	ok(kf_bootarg_disabled("recaulk_kfix=-signal_target_exit,-kqueue_scan_restart", "kqueue_scan_restart") == 1,
	    "bootarg_named_off_list", "the second name of a list leaves it on");
	ok(kf_bootarg_disabled("-v recaulk_kfix=-signal_target_exit debug=0x144", "kqueue_scan_restart") == 0,
	    "bootarg_other_name", "another fix's name turns it off");
	ok(kf_bootarg_disabled("-v debug=0x144", "kqueue_scan_restart") == 0, "bootarg_absent", "no recaulk_kfix turns it off");
	ok(kf_bootarg_disabled("", "kqueue_scan_restart") == 0 && kf_bootarg_disabled(NULL, "kqueue_scan_restart") == 0,
	    "bootarg_empty", "an empty or absent command line turns it off");
	ok(kf_bootarg_disabled("recaulk_kfix=00", "kqueue_scan_restart") == 0
	    && kf_bootarg_disabled("xrecaulk_kfix=0", "kqueue_scan_restart") == 0
	    && kf_bootarg_disabled("recaulk_kfix=-kqueue_scan_restartx", "kqueue_scan_restart") == 0
	    && kf_bootarg_disabled("recaulk_kfix=-kqueue_scan", "kqueue_scan_restart") == 0,
	    "bootarg_lookalike", "a lookalike token turns it off");
	/* ---- hooks ---- */
	{
		/* a synthetic function at 0x1000: padding, the 13F1911-shaped argument set-up, a call to 0x5000, more */
		static const uint8_t before[10] = { 0x48, 0x8b, 0x93, 0xf0, 0x02, 0x00, 0x00, 0x48, 0x89, 0xdf };
		uint8_t fn[64];
		uint64_t at = 0, fa = 0x1000, tgt = 0x5000;
		memset(fn, 0x90, sizeof fn);
		memcpy(fn + 20, before, sizeof before);
		int32_t d = (int32_t)(tgt - (fa + 30 + 5));
		fn[30] = 0xe8;
		memcpy(fn + 31, &d, 4);
		why = NULL;
		ok(kf_find_call(fn, sizeof fn, fa, tgt, before, sizeof before, &at, &why) == 0 && at == fa + 30,
		    "call_unique", "the one call after the set-up was not found where it is");
		ok(kf_find_call(fn, sizeof fn, fa, tgt + 16, before, sizeof before, &at, &why) == ESRCH && why,
		    "call_other_target", "a call to another target was taken");
		uint8_t wrong[10];
		memcpy(wrong, before, sizeof wrong);
		wrong[2] ^= 1;
		ok(kf_find_call(fn, sizeof fn, fa, tgt, wrong, sizeof wrong, &at, &why) == ESRCH, "call_wrong_before",
		    "a call after different set-up bytes was taken");
		uint8_t none[64];
		memset(none, 0x90, sizeof none);
		ok(kf_find_call(none, sizeof none, fa, tgt, before, sizeof before, &at, &why) == ESRCH, "call_none",
		    "a function with no call yielded one");
		uint8_t two[64];
		memcpy(two, fn, sizeof two);
		memcpy(two + 40, before, sizeof before);
		d = (int32_t)(tgt - (fa + 50 + 5));
		two[50] = 0xe8;
		memcpy(two + 51, &d, 4);
		ok(kf_find_call(two, sizeof two, fa, tgt, before, sizeof before, &at, &why) == ESRCH, "call_twice",
		    "two matching calls yielded one");

		ok(kf_store_ok(0x1000 + 60, 4) == 1, "store_in_line", "a 4-byte store at line offset 60 was refused");
		ok(kf_store_ok(0x1000 + 61, 4) == 0, "store_crosses_line", "a store crossing a 64-byte line was allowed");

		int32_t disp = 0;
		ok(kf_rel32(0xffffff8000245a06ULL, 0xffffff800024b5f2ULL, &disp) == 0 && disp == 0x5bec, "rel32_in_range",
		    "an in-range rel32 is wrong");
		ok(kf_rel32(0x1000, 0x1000 + 0x80000000ULL, &disp) == ERANGE, "rel32_out_of_range", "2 GiB away was accepted");
		ok(kf_rel32(0x80001000ULL, 0x1000, &disp) == 0 && disp == INT32_MIN, "rel32_min", "-2 GiB exactly was refused");

		uint8_t gap[15];
		gap[0] = 0xc3;
		memset(gap + 1, 0x90, 14);
		ok(kf_gap_ok(gap, 14), "gap_found", "ret then 14 NOPs is not a gap");
		ok(!kf_gap_ok(gap + 1, 13), "gap_not_after_ret", "a run not after a ret is a gap");
		gap[7] = 0xc3;
		ok(!kf_gap_ok(gap, 14), "gap_not_padding", "a c3 inside the run is a gap");
		gap[7] = 0x90;
		gap[0] = 0x5d;
		ok(!kf_gap_ok(gap, 14), "gap_no_ret", "a run after a non-ret is a gap");

		uint8_t tr[14];
		static const uint8_t want_tr[14] = { 0xff, 0x25, 0, 0, 0, 0, 0x34, 0x12, 0x00, 0x80, 0x7f, 0xff, 0xff, 0xff };
		kf_trampoline(tr, 0xffffff7f80001234ULL);
		ok(memcmp(tr, want_tr, sizeof tr) == 0, "trampoline_bytes", "jmp [rip+0] and the handler are not the bytes");
		/* fbt scans past a function's end into the trampoline and takes "5d or c9, then c3 c2 e9 eb or ea" as a
		   return site to patch (xnu-2422.115.4 bsd/dev/i386/fbt_x86.c); such a handler address is refused */
		ok(kf_trampoline_fbt_safe(tr, 0x55), "fbt_safe", "an ordinary handler address is refused");
		kf_trampoline(tr, 0xffffff7f80c35d12ULL);
		ok(!kf_trampoline_fbt_safe(tr, 0x55), "fbt_pop_ret", "5d c3 in the address is accepted");
		kf_trampoline(tr, 0xffffff7f8000eac9ULL);
		ok(!kf_trampoline_fbt_safe(tr, 0x55), "fbt_leave_jmp", "c9 ea in the address is accepted");
		kf_trampoline(tr, 0xffffff7f80005d00ULL);
		ok(kf_trampoline_fbt_safe(tr, 0x55), "fbt_lone_pop", "5d not before a return-like byte is refused");
	}
	if (argc > 1)
		real_kernel(argv[1]);
	if (failures == 0)
		printf("kfix-engine OK\n");
	return failures != 0;
}
