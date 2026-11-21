/* spec: tests/kext-runtime-test.sh -- dev.mavergreen.recaulk.test.kpi-probe imports all 7 of RecaulkKPI's names, as
   macFUSE's kext does, and calls each from a sysctl under debug.recaulk_kpi_probe on a file the test names:
     notify (write a path)  vfs_get_notify_attributes, vnode_getattr, then vnode_notify(vp, 0xe, &va)
     range  (write a path)  ubc_upl_map_range over the file's first page, when it is resident (else EAGAIN), then buf_map_range on buf_bread's
                            block 0; each copies the file's first bytes into upl_bytes and buf_bytes
     chk    (read)          __memcpy_chk and __strncpy_chk within bounds: 1 when both copied right
   and error, the errno of the last write (0 for success). Never loaded outside a 10.9 test. */
#include <mach/mach_types.h>
#include <mach/kmod.h>
#include <mach/vm_prot.h>
#include <sys/types.h>
#include <sys/errno.h>
#include <sys/buf.h>
#include <sys/kauth.h>
#include <sys/sysctl.h>
#include <sys/ubc.h>
#include <sys/vnode.h>
#include <string.h>

extern int printf(const char *, ...);
/* the 7, declared as macFUSE 5.5.0's kext declares them (xnu-8019.41.5's prototypes) */
void *__memcpy_chk(void *dst, const void *src, size_t len, size_t dstlen);
char *__strncpy_chk(char *dst, const char *src, size_t len, size_t dstlen);
kern_return_t ubc_upl_map_range(upl_t upl, vm_offset_t offset, vm_size_t size, vm_prot_t prot, vm_offset_t *dst_addr);
errno_t buf_map_range(buf_t bp, caddr_t *io_addr);
errno_t buf_unmap_range(buf_t bp);
int vfs_get_notify_attributes(struct vnode_attr *vap);
int vnode_notify(vnode_t vp, uint32_t events, struct vnode_attr *vap);

#define PROBE_BYTES 16
static int last_error;
static char path[1024];
static char upl_bytes[PROBE_BYTES + 1];
static char buf_bytes[PROBE_BYTES + 1];

static void
copy_bytes(char *to, const char *from)
{
	int i;

	for (i = 0; i < PROBE_BYTES && from[i] != '\0' && from[i] != '\n'; i++) {
		to[i] = from[i];
	}
	to[i] = '\0';
}

static int
with_vnode(int (*fn)(vnode_t, vfs_context_t))
{
	vfs_context_t ctx = vfs_context_create(NULL);
	vnode_t vp = NULLVP;
	int err;

	if (ctx == NULL) {
		return ENOMEM;
	}
	if ((err = vnode_lookup(path, 0, &vp, ctx)) == 0) {
		err = fn(vp, ctx);
		vnode_put(vp);
	}
	vfs_context_rele(ctx);
	return err;
}

static int
do_notify(vnode_t vp, vfs_context_t ctx)
{
	struct vnode_attr va;
	int err;

	if ((err = vfs_get_notify_attributes(&va)) != 0) {
		return err;
	}
	if ((err = vnode_getattr(vp, &va, ctx)) != 0) {
		return err;
	}
	/* VNODE_EVENT_WRITE | VNODE_EVENT_EXTEND | VNODE_EVENT_ATTRIB */
	return vnode_notify(vp, 0xe, &va);
}

static int
do_range(vnode_t vp, vfs_context_t ctx)
{
	upl_t upl = NULL;
	upl_page_info_t *pl = NULL;
	vm_offset_t a = 0;
	buf_t bp = NULL;
	caddr_t b = NULL;
	int err;

	upl_bytes[0] = buf_bytes[0] = '\0';
	if (ubc_create_upl(vp, 0, PAGE_SIZE, &upl, &pl, UPL_FILE_IO | UPL_SET_LITE) != KERN_SUCCESS || upl == NULL) {
		return EIO;
	}
	/* ubc_create_upl hands back an absent page as a fresh one, not the file's: read only a valid page
	   (xnu-2422.115.4 osfmk/vm/vm_pageout.c, vm_object_upl_request); the test reads the file first */
	if (!upl_valid_page(pl, 0)) {
		ubc_upl_abort(upl, UPL_ABORT_FREE_ON_EMPTY);
		return EAGAIN;
	}
	if (ubc_upl_map_range(upl, 0, PAGE_SIZE, VM_PROT_READ, &a) != KERN_SUCCESS) {
		ubc_upl_abort(upl, UPL_ABORT_FREE_ON_EMPTY);
		return EFAULT;
	}
	copy_bytes(upl_bytes, (const char *)a);
	ubc_upl_unmap(upl);
	ubc_upl_abort(upl, UPL_ABORT_FREE_ON_EMPTY);

	if ((err = buf_bread(vp, 0, PAGE_SIZE, vfs_context_ucred(ctx), &bp)) != 0) {
		if (bp != NULL) {
			buf_brelse(bp);
		}
		return err;
	}
	if ((err = buf_map_range(bp, &b)) == 0) {
		copy_bytes(buf_bytes, (const char *)b);
		err = buf_unmap_range(bp);
	}
	buf_markinvalid(bp);
	buf_brelse(bp);
	return err;
}

static int
sysctl_path_op(struct sysctl_oid *oidp, void *arg1, int arg2, struct sysctl_req *req)
{
	int (*fn)(vnode_t, vfs_context_t) = arg2 == 0 ? do_notify : do_range;
	int err;

	(void)oidp;
	(void)arg1;
	path[0] = '\0';
	err = sysctl_handle_string(oidp, path, sizeof path, req);
	if (err != 0 || req->newptr == USER_ADDR_NULL) {
		return err;
	}
	last_error = with_vnode(fn);
	return 0;
}

static int
sysctl_chk(struct sysctl_oid *oidp, void *arg1, int arg2, struct sysctl_req *req)
{
	char a[8], b[8];
	volatile size_t n = 6;
	int ok;

	(void)arg1;
	(void)arg2;
	__memcpy_chk(a, "probe", n, sizeof a);
	__strncpy_chk(b, "probe", sizeof b, sizeof b);
	ok = memcmp(a, "probe", 6) == 0 && memcmp(b, "probe\0\0\0", 8) == 0;
	return sysctl_handle_int(oidp, &ok, 0, req);
}

SYSCTL_DECL(_debug);
SYSCTL_NODE(_debug, OID_AUTO, recaulk_kpi_probe, CTLFLAG_RW | CTLFLAG_LOCKED, 0, "RecaulkKPI's test probe");
SYSCTL_PROC(_debug_recaulk_kpi_probe, OID_AUTO, notify, CTLTYPE_STRING | CTLFLAG_RW | CTLFLAG_LOCKED, NULL, 0,
    sysctl_path_op, "A", "vnode_notify(path, 0xe)");
SYSCTL_PROC(_debug_recaulk_kpi_probe, OID_AUTO, range, CTLTYPE_STRING | CTLFLAG_RW | CTLFLAG_LOCKED, NULL, 1,
    sysctl_path_op, "A", "map path's first page through the *_range calls");
SYSCTL_PROC(_debug_recaulk_kpi_probe, OID_AUTO, chk, CTLTYPE_INT | CTLFLAG_RD | CTLFLAG_LOCKED, NULL, 0,
    sysctl_chk, "I", "the _chk copies, within bounds");
SYSCTL_INT(_debug_recaulk_kpi_probe, OID_AUTO, error, CTLFLAG_RD | CTLFLAG_LOCKED, &last_error, 0, "the last write's errno");
SYSCTL_STRING(_debug_recaulk_kpi_probe, OID_AUTO, upl_bytes, CTLFLAG_RD | CTLFLAG_LOCKED, upl_bytes, 0, "");
SYSCTL_STRING(_debug_recaulk_kpi_probe, OID_AUTO, buf_bytes, CTLFLAG_RD | CTLFLAG_LOCKED, buf_bytes, 0, "");

static struct sysctl_oid *oids[] = {
	&sysctl__debug_recaulk_kpi_probe, &sysctl__debug_recaulk_kpi_probe_notify, &sysctl__debug_recaulk_kpi_probe_range,
	&sysctl__debug_recaulk_kpi_probe_chk, &sysctl__debug_recaulk_kpi_probe_error,
	&sysctl__debug_recaulk_kpi_probe_upl_bytes, &sysctl__debug_recaulk_kpi_probe_buf_bytes,
};
#define NOIDS (sizeof oids / sizeof oids[0])

static kern_return_t
probe_start(kmod_info_t *ki, void *data)
{
	unsigned i;

	(void)ki;
	(void)data;
	for (i = 0; i < NOIDS; i++) {
		sysctl_register_oid(oids[i]);
	}
	printf("RecaulkKPIProbe: started\n");
	return KERN_SUCCESS;
}

static kern_return_t
probe_stop(kmod_info_t *ki, void *data)
{
	unsigned i;

	(void)ki;
	(void)data;
	for (i = NOIDS; i > 0; i--) {
		sysctl_unregister_oid(oids[i - 1]);
	}
	return KERN_SUCCESS;
}

extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(dev.mavergreen.recaulk.test.kpi-probe, RECAULK_KPI_VERSION, _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = probe_start;
__private_extern__ kmod_stop_func_t *_antimain = probe_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
