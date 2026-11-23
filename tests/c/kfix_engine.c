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
static const struct kf_patch P = { "demo", { 0 }, NULL, 0, expect, replace, sizeof expect };

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
		{ "_uthread_cleanup", 0, 0 }, { "_timer_call_init", 0, 0 }, { "_kqueue_scan", 0, 0 } };
	struct rk_mem mem = { m_alloc, m_free };
	struct rk_kernel k;
	struct stat sb;
	const char *why = NULL;
	if ((kfd = open(path, O_RDONLY)) < 0 || fstat(kfd, &sb) != 0) {
		ok(0, "real_kernel", "cannot open the kernel file");
		return;
	}
	struct rk_file f = { NULL, (uint64_t)sb.st_size, fd_read };
	if (rk_read_kernel(&f, &mem, &k, want, 5, &why) != 0) {
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
	static const uint8_t kq_head[5] = { 0x48, 0x8d, 0x3d, 0xbb, 0xf3 };
	f.read(NULL, kq, sizeof kq, want[4].value + 0x8dc - k.text_vmaddr);
	ok(memcmp(kq, kq_head, sizeof kq_head) == 0 && kq[19] == 0xe8, "real_kqueue_site",
	    "_kqueue_scan+0x8dc does not start the panic call's set-up");
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
	}
	if (argc > 1)
		real_kernel(argv[1]);
	if (failures == 0)
		printf("kfix-engine OK\n");
	return failures != 0;
}
