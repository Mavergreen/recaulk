/* RecaulkKernelFixes' pure engine (src/kfix/engine.c) on synthetic bytes, in userspace: a patch site that holds
   the expected bytes, the replacement already, or neither; UUID comparison; and the recaulk_kfix boot-arg. */
#include <errno.h>
#include <stdio.h>
#include <string.h>
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

int
main(void)
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
	if (failures == 0)
		printf("kfix-engine OK\n");
	return failures != 0;
}
