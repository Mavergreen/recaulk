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

struct vfile {
	vnode_t vp;
	vfs_context_t ctx;
};

static int
vread(void *c, void *buf, size_t len, uint64_t off)
{
	struct vfile *v = c;
	int resid = 0, err;

	if (len > 0x7fffffff) {
		return EFBIG;
	}
	err = vn_rdwr(UIO_READ, v->vp, (caddr_t)buf, (int)len, (off_t)off, UIO_SYSSPACE, 0,
	    vfs_context_ucred(v->ctx), &resid, vfs_context_proc(v->ctx));
	return err != 0 ? err : resid != 0 ? EIO : 0;
}

static void *
kalloc_temp(size_t len)
{
	return _MALLOC(len, M_TEMP, M_WAITOK);
}

static void
kfree_temp(void *p, size_t len)
{
	(void)len;
	_FREE(p, M_TEMP);
}

static int
resolve(vnode_notify_fn *out, uint64_t *slide_out, const char **why)
{
	static const struct rk_mem mem = { kalloc_temp, kfree_temp };
	struct rk_sym want[] = {
		{ "_vnode_notify", 0, 0 }, { "_printf", 0, 0 }, { "_panic", 0, 0 }, { "_vnode_isdir", 0, 0 },
	};
	const uint64_t live[] = {
		0, (uint64_t)(uintptr_t)&printf, (uint64_t)(uintptr_t)&panic, (uint64_t)(uintptr_t)&vnode_isdir,
	};
	const unsigned nwant = sizeof(want) / sizeof(want[0]);
	struct vfile v = { NULLVP, NULL };
	struct vnode_attr va;
	struct rk_kernel k;
	uint8_t running[16];
	uint64_t slide = 0, target;
	int err;

	*why = "unknown";
	if ((v.ctx = vfs_context_create(NULL)) == NULL) {
		*why = "vfs_context_create failed";
		return ENOMEM;
	}
	/* A-m3: opened, so the filesystem sees VNOP_OPEN before any read */
	if ((err = vnode_open(RECAULK_KPI_KERNEL_PATH, FREAD, 0, 0, &v.vp, v.ctx)) != 0) {
		*why = "cannot open " RECAULK_KPI_KERNEL_PATH;
		v.vp = NULLVP;
		goto done;
	}
	VATTR_INIT(&va);
	VATTR_WANTED(&va, va_data_size);
	if (!vnode_isreg(v.vp)) {
		*why = RECAULK_KPI_KERNEL_PATH " is not a regular file";
		err = EINVAL;
		goto done;
	}
	if ((err = vnode_getattr(v.vp, &va, v.ctx)) != 0 || !VATTR_IS_SUPPORTED(&va, va_data_size)) {
		*why = "cannot read " RECAULK_KPI_KERNEL_PATH "'s size";
		err = err ? err : EINVAL;
		goto done;
	}
	{
		struct rk_file f = { &v, va.va_data_size, vread };
		if ((err = rk_read_kernel(&f, &mem, &k, want, nwant, why)) != 0) {
			goto done;
		}
	}
	if ((err = rk_slide(want, live, nwant, &slide, why)) != 0) {
		goto done;
	}
	/* review M1: a corrupt or foreign file can agree on a wrong slide; its __TEXT, moved, must hold the live symbols
	   before the live header there is read */
	if ((err = rk_live_in_text(&k, live, nwant, slide, why)) != 0) {
		goto done;
	}
	if (want[0].value < k.text_vmaddr || want[0].value - k.text_vmaddr >= k.text_vmsize) {
		*why = "_vnode_notify lies outside the kernel's __TEXT";
		err = EINVAL;
		goto done;
	}
	/* The running kernel's own header, read only once three symbols agree on the slide. */
	if (rk_header_uuid((const void *)(uintptr_t)(k.text_vmaddr + slide), running) != 0 ||
	    memcmp(running, k.uuid, sizeof(running)) != 0) {
		*why = "the running kernel's UUID differs from " RECAULK_KPI_KERNEL_PATH "'s (an update awaiting reboot?)";
		err = ESRCH;
		goto done;
	}
	target = want[0].value + slide;
	if ((uintptr_t)target == (uintptr_t)&vnode_notify) {
		*why = "resolved to this kext's own vnode_notify";
		err = ELOOP;
		goto done;
	}
	*out = (vnode_notify_fn)(uintptr_t)target;
	*slide_out = slide;
	err = 0;
done:
	if (v.vp != NULLVP) {
		vnode_close(v.vp, FREAD, v.ctx);
	}
	vfs_context_rele(v.ctx);
	return err;
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
