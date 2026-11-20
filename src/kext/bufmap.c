/* spec: README.md "The kernel back-fill kext" -- the *_range mapping KPIs macFUSE imports, which arrived in
   xnu-8019.41.5, over 10.9's whole-UPL and legacy buf calls. Each points at the same byte as upstream's. */
#include <mach/mach_types.h>
#include <mach/vm_prot.h>
#include <sys/types.h>
#include <sys/errno.h>
#include <sys/buf.h>
#include <sys/ubc.h>

#define RK_EXPORT __attribute__((visibility("default"), used))

/* xnu-8019.41.5 osfmk/vm/vm_user.c:2495-2516 (vm_upl_map_range) maps the pages covering [offset, offset+size)
   at prot and returns the address of the byte at offset. 10.9 has only ubc_upl_map: the whole UPL, read-write.
   Deviations: size is ignored (more kernel VA is mapped), and prot is ignored (always read-write, a superset).
   ubc_upl_unmap, and so buf_unmap_range below, removes the UPL's one mapping on both kernels, whatever the
   offset and size. On failure *dst_addr is left as it was. */
RK_EXPORT kern_return_t
ubc_upl_map_range(upl_t upl, vm_offset_t offset, vm_size_t size, vm_prot_t prot, vm_offset_t *dst_addr)
{
	vm_offset_t base = 0;
	kern_return_t kr;

	(void)size;
	(void)prot;
	kr = ubc_upl_map(upl, &base);
	if (kr != KERN_SUCCESS) {
		return kr;
	}
	*dst_addr = base + offset;
	return KERN_SUCCESS;
}

/* xnu-8019.41.5 bsd/vfs/vfs_bio.c:1154-1202: buf_map_range is buf_map but for mapping a UPL with
   ubc_upl_map_range(b_upl, b_uploffset, ...) in place of ubc_upl_map(b_upl) + b_uploffset; both give the byte
   at b_uploffset. 10.9's buf_map (xnu-2422.115.4 vfs_bio.c:1016) is the legacy path word for word. */
RK_EXPORT errno_t
buf_map_range(buf_t bp, caddr_t *io_addr)
{
	return buf_map(bp, io_addr);
}

/* xnu-8019.41.5 bsd/vfs/vfs_bio.c:1211-1259: buf_unmap but for ubc_upl_unmap_range, which ignores offset and
   size (osfmk/vm/vm_pageout.c:7249). Inherited upstream edge, unchanged here: macFUSE maps any B_CLUSTER buf's
   UPL itself, but buf_unmap_range skips a cluster buf whose b_real_bp is already mapped, so that mapping is
   never removed and a later map of the UPL fails. macOS 12+ with the real KPIs behaves the same. */
RK_EXPORT errno_t
buf_unmap_range(buf_t bp)
{
	return buf_unmap(bp);
}
