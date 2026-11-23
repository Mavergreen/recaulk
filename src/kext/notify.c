/* spec: README.md "The kernel back-fill kext" -- vfs_get_notify_attributes and vnode_notify, which 10.9 exports
   only through com.apple.kpi.private (xnu-2422.115.4 libkern/c++/OSKext.cpp:7267-7297: Apple's kexts only).
   vnode_notify forwards to the running kernel's own function, found in /mach_kernel's symbol table on first
   use; when that fails it reports success and delivers nothing, and says why once. */
#include <mach/mach_types.h>
#include <kern/debug.h>
#include <kern/locks.h>
#include <kern/sched_prim.h>
#include <kern/thread.h>
#include <libkern/OSAtomic.h>
#include <sys/types.h>
#include <sys/errno.h>
#include <sys/fcntl.h>
#include <sys/malloc.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <sys/uio.h>
#include <sys/vnode.h>
#include <string.h>
#include "core.h"
#include "kext.h"
#include "kresolve.h"

#define RK_EXPORT __attribute__((visibility("default"), used))

extern int printf(const char *, ...);
/* platform: 10.9's SDK declares neither: both are KERNEL_PRIVATE in xnu-2422.115.4 bsd/sys/vnode.h */
int vfs_get_notify_attributes(struct vnode_attr *vap);
int vnode_notify(vnode_t vp, uint32_t events, struct vnode_attr *vap);

/* xnu-2422.115.4 bsd/vfs/kpi_vfs.c:2672-2678: VATTR_INIT, then va_active = VNODE_NOTIFY_ATTRS, which is
   BSD_KERNEL_PRIVATE (bsd/sys/vnode.h:1428-1434) and so spelled out here. */
#define RK_VNODE_NOTIFY_ATTRS (VNODE_ATTR_BIT(va_fsid) | VNODE_ATTR_BIT(va_fileid) | VNODE_ATTR_BIT(va_mode) | \
	VNODE_ATTR_BIT(va_uid) | VNODE_ATTR_BIT(va_gid) | VNODE_ATTR_BIT(va_dirlinkcount) | VNODE_ATTR_BIT(va_nlink))

RK_EXPORT int
vfs_get_notify_attributes(struct vnode_attr *vap)
{
	VATTR_INIT(vap);
	vap->va_active = RK_VNODE_NOTIFY_ATTRS;
	return 0;
}

/* ---- the forwarded-call counter: debug.recaulk_kpi.vnode_notify_forwarded ---- */
static uint64_t forwarded;
SYSCTL_DECL(_debug);
SYSCTL_NODE(_debug, OID_AUTO, recaulk_kpi, CTLFLAG_RW | CTLFLAG_LOCKED, 0, "RecaulkKPI.kext");
SYSCTL_QUAD(_debug_recaulk_kpi, OID_AUTO, vnode_notify_forwarded, CTLFLAG_RD | CTLFLAG_LOCKED, &forwarded,
    "vnode_notify calls forwarded to the kernel's own");

/* ---- resolution, once ---- */
typedef int (*vnode_notify_fn)(vnode_t, uint32_t, struct vnode_attr *);
enum { UNRESOLVED, RESOLVING, RESOLVED };
static int state = UNRESOLVED;		/* read without the lock: acquire; written under it: release */
static vnode_notify_fn kernel_vnode_notify;
static lck_grp_t *grp;
static lck_mtx_t *lock;

#ifndef RECAULK_KPI_KERNEL_PATH
#define RECAULK_KPI_KERNEL_PATH "/mach_kernel"
#endif

static int
resolve(vnode_notify_fn *out, uint64_t *slide_out, const char **why)
{
	struct rk_sym want[] = {
		{ "_vnode_notify", 0, 0 }, { "_printf", 0, 0 }, { "_panic", 0, 0 }, { "_vnode_isdir", 0, 0 },
	};
	const uint64_t live[] = {
		0, (uint64_t)(uintptr_t)&printf, (uint64_t)(uintptr_t)&panic, (uint64_t)(uintptr_t)&vnode_isdir,
	};
	const unsigned nwant = sizeof(want) / sizeof(want[0]);
	struct rk_kernel k;
	uint64_t slide = 0, target;
	int err;

	if ((err = rk_resolve_live(want, live, nwant, &k, &slide, why)) != 0) {
		return err;
	}
	if (want[0].value < k.text_vmaddr || want[0].value - k.text_vmaddr >= k.text_vmsize) {
		*why = "_vnode_notify lies outside the kernel's __TEXT";
		return EINVAL;
	}
	target = want[0].value + slide;
	if ((uintptr_t)target == (uintptr_t)&vnode_notify) {
		*why = "resolved to this kext's own vnode_notify";
		return ELOOP;
	}
	*out = (vnode_notify_fn)(uintptr_t)target;
	*slide_out = slide;
	return 0;
}

/* review I1: resolution runs on a kernel thread of its own, so the kernel's credentials and the real root open
   /mach_kernel, never those of whichever process made macFUSE call first (chrooted, or sandboxed away from it),
   and its reads do not deepen a filesystem call's stack. The caller waits for it, under the lock. */
static struct {
	int done;
	vnode_notify_fn fn;
	uint64_t slide;
	const char *why;
	int err;
} job;

static void
resolve_thread(void *arg, wait_result_t wr)
{
	(void)arg;
	(void)wr;
	job.err = resolve(&job.fn, &job.slide, &job.why);
	lck_mtx_lock(lock);
	job.done = 1;
	thread_wakeup((event_t)&job);
	lck_mtx_unlock(lock);
	/* Nothing after the unlock touches the kext's data, and kextd unloads it only after every kext linking it,
	   which cannot happen before the caller this thread woke has returned. */
}

/* A-m4: resolution waits for root to be mounted (a prelinked or early load has none), runs once, under the
   lock, and is never retried after it decides. */
static vnode_notify_fn
kernel_fn(void)
{
	thread_t t;
	vnode_t root;

	if (__atomic_load_n(&state, __ATOMIC_ACQUIRE) == RESOLVED) {
		return kernel_vnode_notify;
	}
	lck_mtx_lock(lock);
	if (state == UNRESOLVED) {
		if ((root = vfs_rootvnode()) == NULLVP) {
			lck_mtx_unlock(lock);
			return NULL;	/* not yet: the next call tries again */
		}
		vnode_put(root);
		state = RESOLVING;
		job.done = 0;
		if (kernel_thread_start(resolve_thread, NULL, &t) != KERN_SUCCESS) {
			job.err = ENOMEM;
			job.why = "cannot start the resolving thread";
			job.done = 1;
		} else {
			thread_deallocate(t);
		}
		while (!job.done) {
			lck_mtx_sleep(lock, LCK_SLEEP_DEFAULT, (event_t)&job, THREAD_UNINT);
		}
		if (job.err == 0) {
			kernel_vnode_notify = job.fn;
			printf(RK_LOG "vnode_notify: forwarding to kernel %p (slide 0x%llx, " RECAULK_KPI_KERNEL_PATH
			    " UUID matches)\n", (void *)job.fn, (unsigned long long)job.slide);
		} else {
			kernel_vnode_notify = NULL;
			printf(RK_LOG "vnode_notify: FALLBACK, delivering nothing (%s, error %d)\n", job.why, job.err);
		}
		__atomic_store_n(&state, RESOLVED, __ATOMIC_RELEASE);
		thread_wakeup((event_t)&state);
	} else {
		while (state == RESOLVING) {
			lck_mtx_sleep(lock, LCK_SLEEP_DEFAULT, (event_t)&state, THREAD_UNINT);
		}
	}
	lck_mtx_unlock(lock);
	return kernel_vnode_notify;
}

RK_EXPORT int
vnode_notify(vnode_t vp, uint32_t events, struct vnode_attr *vap)
{
	vnode_notify_fn fn = kernel_fn();

	if (fn == NULL) {
		return 0;
	}
	OSAddAtomic64(1, (volatile SInt64 *)&forwarded);
	return fn(vp, events, vap);
}

int
rk_notify_start(void)
{
	if ((grp = lck_grp_alloc_init("dev.mavergreen.recaulk.kpi", LCK_GRP_ATTR_NULL)) == NULL) {
		return ENOMEM;
	}
	if ((lock = lck_mtx_alloc_init(grp, LCK_ATTR_NULL)) == NULL) {
		lck_grp_free(grp);
		grp = NULL;
		return ENOMEM;
	}
	sysctl_register_oid(&sysctl__debug_recaulk_kpi);
	sysctl_register_oid(&sysctl__debug_recaulk_kpi_vnode_notify_forwarded);
	return 0;
}

void
rk_notify_stop(void)
{
	/* No caller remains: kextd unloads this kext only after every kext that links it. */
	sysctl_unregister_oid(&sysctl__debug_recaulk_kpi_vnode_notify_forwarded);
	sysctl_unregister_oid(&sysctl__debug_recaulk_kpi);
	lck_mtx_free(lock, grp);
	lck_grp_free(grp);
	lock = NULL;
	grp = NULL;
	kernel_vnode_notify = NULL;
	state = UNRESOLVED;
}
