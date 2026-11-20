/* spec: README.md "The kernel back-fill kext" -- the kext's pure parts: the version gate, and reading the
   running kernel's file for the symbols vnode_notify forwarding needs. No kernel call happens here, so the
   same file builds into the kext and into tests/c/kext_core.c, which feeds it malformed kernels. */
#ifndef RECAULK_KPI_CORE_H
#define RECAULK_KPI_CORE_H
/* platform: <sys/types.h> gives size_t and uint*_t in the kernel's headers and userland's alike; the kernel's
   have no <stddef.h> */
#include <sys/types.h>

/* The kernel file, read through the caller: a vnode in the kext, a buffer or a file descriptor in a test.
   read returns 0 or an errno, and fails a short read. */
struct rk_file {
	void *ctx;
	uint64_t size;
	int (*read)(void *ctx, void *buf, size_t len, uint64_t off);
};
struct rk_mem {
	void *(*alloc)(size_t len);
	void (*free)(void *p, size_t len);
};
struct rk_sym {
	const char *name;
	uint64_t value;		/* unslid, from the file */
	int found;
};
struct rk_kernel {
	uint8_t uuid[16];
	uint64_t text_vmaddr;
	uint64_t text_vmsize;
};

/* platform: xnu-2422.115.4's symbol and string tables (/mach_kernel 10.9.5) are 294 KiB and 486 KiB; a bigger
   claim is a malformed file */
#define RK_SYMTAB_CAP	(4u << 20)
#define RK_STRTAB_CAP	(4u << 20)
/* The first RK_HEADER_READ bytes of the file hold the Mach header and its load commands. */
#define RK_HEADER_READ	8192u
/* The running kernel's own header: its load commands are a few KiB; a bigger sizeofcmds is not believed. */
#define RK_LIVE_CMDS_CAP	65536u

int rk_kernel_supported(int darwin_major);
/* Fills k and every want[i] (value, found), or returns an errno with *why set. Every allocation it makes
   through m is freed before it returns. */
int rk_read_kernel(const struct rk_file *f, const struct rk_mem *m, struct rk_kernel *k,
    struct rk_sym *want, unsigned nwant, const char **why);
/* The slide every want[i] with live[i] != 0 agrees on, page aligned; else ESRCH with *why set. */
int rk_slide(const struct rk_sym *want, const uint64_t *live, unsigned nwant, uint64_t *slide, const char **why);
/* The UUID of an in-memory 64-bit Mach header, its load-command walk bounded by sizeofcmds; 0 if found. */
int rk_header_uuid(const void *mh, uint8_t uuid[16]);
#endif
