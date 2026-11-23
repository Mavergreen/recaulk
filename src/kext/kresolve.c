/* spec: README.md "The kernel back-fill kext" -- the running kernel's file read for symbols: opened as a vnode (the
   kernel's credentials, from a kernel thread), its symbols' slide agreed by the live addresses the caller passes,
   their __TEXT checked, and the running kernel's own UUID matched against the file's. RecaulkKPI's vnode_notify
   and RecaulkKernelFixes share it. It may block on I/O, so it runs in thread context only. */
#include <mach/mach_types.h>
#include <sys/types.h>
#include <sys/errno.h>
#include <sys/fcntl.h>
#include <sys/malloc.h>
#include <sys/mount.h>
#include <sys/uio.h>
#include <sys/vnode.h>
#include <string.h>
#include "core.h"
#include "kresolve.h"

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

int
rk_resolve_live(struct rk_sym *want, const uint64_t *live, unsigned nwant, struct rk_kernel *k, uint64_t *slide_out,
    const char **why)
{
	static const struct rk_mem mem = { kalloc_temp, kfree_temp };
	struct vfile v = { NULLVP, NULL };
	struct vnode_attr va;
	uint8_t running[16];
	uint64_t slide = 0;
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
		if ((err = rk_read_kernel(&f, &mem, k, want, nwant, why)) != 0) {
			goto done;
		}
	}
	if ((err = rk_slide(want, live, nwant, &slide, why)) != 0) {
		goto done;
	}
	/* review M1: a corrupt or foreign file can agree on a wrong slide; its __TEXT, moved, must hold the live symbols
	   before the live header there is read */
	if ((err = rk_live_in_text(k, live, nwant, slide, why)) != 0) {
		goto done;
	}
	/* The running kernel's own header, read only once the live symbols agree on the slide. */
	if (rk_header_uuid((const void *)(uintptr_t)(k->text_vmaddr + slide), running) != 0 ||
	    memcmp(running, k->uuid, sizeof(running)) != 0) {
		*why = "the running kernel's UUID differs from " RECAULK_KPI_KERNEL_PATH "'s (an update awaiting reboot?)";
		err = ESRCH;
		goto done;
	}
	*slide_out = slide;
	err = 0;
done:
	if (v.vp != NULLVP) {
		vnode_close(v.vp, FREAD, v.ctx);
	}
	vfs_context_rele(v.ctx);
	return err;
}
