/* spec: README.md "The kernel back-fill kext" -- see core.h. Every read of the file is bounded by the file's
   size, every load-command walk by sizeofcmds, and every allocation by both the file and a cap. */
#include <sys/errno.h>
#include <string.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <libkern/OSByteOrder.h>
#include "core.h"

/* spec: README.md "The kernel back-fill kext" -- the kext starts only on Darwin 13 (10.9): its back-fills
   follow xnu-2422's internals, and a later kernel exports the real functions */
#ifndef RECAULK_KPI_DARWIN_MAJOR
#define RECAULK_KPI_DARWIN_MAJOR 13
#endif

int
rk_kernel_supported(int darwin_major)
{
	return darwin_major == RECAULK_KPI_DARWIN_MAJOR;
}

/* [off, off+len) lies within [0, size) */
static int
within(uint64_t off, uint64_t len, uint64_t size)
{
	return off <= size && len <= size - off;
}

static int
fail(const char **why, const char *reason, int err)
{
	*why = reason;
	return err;
}

/* The x86_64 slice's offset and size, for a thin or a fat file. */
static int
find_slice(const struct rk_file *f, const uint8_t *hdr, size_t got, uint64_t *off, uint64_t *size,
    const char **why)
{
	const struct fat_header *fh = (const struct fat_header *)(const void *)hdr;
	const struct fat_arch *fa = (const struct fat_arch *)(const void *)(fh + 1);
	uint32_t n, i;

	if (got < sizeof(*fh) || OSSwapBigToHostInt32(fh->magic) != FAT_MAGIC) {
		*off = 0;
		*size = f->size;
		return 0;
	}
	n = OSSwapBigToHostInt32(fh->nfat_arch);
	if (n > (got - sizeof(*fh)) / sizeof(*fa)) {
		return fail(why, "bad fat header", EINVAL);
	}
	for (i = 0; i < n; i++) {
		if ((cpu_type_t)OSSwapBigToHostInt32((uint32_t)fa[i].cputype) == CPU_TYPE_X86_64) {
			*off = OSSwapBigToHostInt32(fa[i].offset);
			*size = OSSwapBigToHostInt32(fa[i].size);
			if (!within(*off, *size, f->size)) {
				return fail(why, "x86_64 slice runs past the file", EINVAL);
			}
			return 0;
		}
	}
	return fail(why, "no x86_64 slice", EINVAL);
}

int
rk_read_kernel(const struct rk_file *f, const struct rk_mem *m, struct rk_kernel *k,
    struct rk_sym *want, unsigned nwant, const char **why)
{
	uint8_t *hdr = NULL;
	struct nlist_64 *syms = NULL;
	char *strs = NULL;
	size_t hdrsz = 0, hdralloc = 0, symsz = 0, strsz = 0;
	uint64_t base = 0, slice = 0;
	const struct mach_header_64 *mh;
	const struct symtab_command *st = NULL;
	const struct uuid_command *uc = NULL;
	const struct segment_command_64 *text = NULL;
	const uint8_t *lc, *end;
	uint32_t i;
	unsigned w;
	int err;

	*why = "unknown";
	hdrsz = f->size < RK_HEADER_READ ? (size_t)f->size : RK_HEADER_READ;
	if (hdrsz < sizeof(struct mach_header_64)) {
		return fail(why, "shorter than a Mach header", EINVAL);
	}
	hdralloc = hdrsz;
	if ((hdr = m->alloc(hdralloc)) == NULL) {
		return fail(why, "allocation failed", ENOMEM);
	}
	if ((err = f->read(f->ctx, hdr, hdrsz, 0)) != 0) {
		fail(why, "read of the header failed", err);
		goto done;
	}
	if ((err = find_slice(f, hdr, hdrsz, &base, &slice, why)) != 0) {
		goto done;
	}
	if (base != 0) {
		hdrsz = slice < RK_HEADER_READ ? (size_t)slice : RK_HEADER_READ;
		if (hdrsz < sizeof(struct mach_header_64)) {
			err = fail(why, "x86_64 slice shorter than a Mach header", EINVAL);
			goto done;
		}
		if ((err = f->read(f->ctx, hdr, hdrsz, base)) != 0) {
			fail(why, "read of the x86_64 slice's header failed", err);
			goto done;
		}
	}
	mh = (const struct mach_header_64 *)(const void *)hdr;
	if (mh->magic != MH_MAGIC_64 || mh->cputype != CPU_TYPE_X86_64 || mh->filetype != MH_EXECUTE) {
		err = fail(why, "not an x86_64 MH_EXECUTE kernel", EINVAL);
		goto done;
	}
	if (mh->sizeofcmds > hdrsz - sizeof(*mh)) {
		err = fail(why, "load commands larger than the header read", EINVAL);
		goto done;
	}
	/* A-m1: each command lies wholly within sizeofcmds, and is at least as long as the struct it is read as. */
	lc = (const uint8_t *)(mh + 1);
	end = lc + mh->sizeofcmds;
	for (i = 0; i < mh->ncmds; i++) {
		const struct load_command *c = (const struct load_command *)(const void *)lc;
		if ((size_t)(end - lc) < sizeof(*c) || c->cmdsize < sizeof(*c) || c->cmdsize > (size_t)(end - lc)) {
			err = fail(why, "bad load commands", EINVAL);
			goto done;
		}
		if (c->cmd == LC_SYMTAB) {
			if (c->cmdsize < sizeof(*st)) {
				err = fail(why, "short LC_SYMTAB", EINVAL);
				goto done;
			}
			st = (const struct symtab_command *)(const void *)c;
		} else if (c->cmd == LC_UUID) {
			if (c->cmdsize < sizeof(*uc)) {
				err = fail(why, "short LC_UUID", EINVAL);
				goto done;
			}
			uc = (const struct uuid_command *)(const void *)c;
		} else if (c->cmd == LC_SEGMENT_64) {
			const struct segment_command_64 *s = (const struct segment_command_64 *)(const void *)c;
			if (c->cmdsize < sizeof(*s)) {
				err = fail(why, "short LC_SEGMENT_64", EINVAL);
				goto done;
			}
			if (strncmp(s->segname, SEG_TEXT, sizeof(s->segname)) == 0) {
				text = s;
			}
		}
		lc += c->cmdsize;
	}
	if (st == NULL || uc == NULL || text == NULL || text->fileoff != 0) {
		err = fail(why, "missing LC_SYMTAB, LC_UUID or __TEXT at file offset 0", EINVAL);
		goto done;
	}
	memcpy(k->uuid, uc->uuid, sizeof(k->uuid));
	k->text_vmaddr = text->vmaddr;
	k->text_vmsize = text->vmsize;

	/* A-m5: both tables lie within the slice, and under the caps, before anything their size is allocated. */
	symsz = (size_t)st->nsyms * sizeof(struct nlist_64);
	strsz = st->strsize;
	if (st->nsyms == 0 || strsz == 0 || symsz > RK_SYMTAB_CAP || strsz > RK_STRTAB_CAP ||
	    !within(st->symoff, symsz, slice) || !within(st->stroff, strsz, slice)) {
		err = fail(why, "symbol or string table implausible for the file", EINVAL);
		goto done;
	}
	syms = m->alloc(symsz);
	strs = m->alloc(strsz);
	if (syms == NULL || strs == NULL) {
		err = fail(why, "allocation failed", ENOMEM);
		goto done;
	}
	if ((err = f->read(f->ctx, syms, symsz, base + st->symoff)) != 0 ||
	    (err = f->read(f->ctx, strs, strsz, base + st->stroff)) != 0) {
		fail(why, "read of the symbol or string table failed", err);
		goto done;
	}
	for (w = 0; w < nwant; w++) {
		want[w].found = 0;
	}
	for (i = 0; i < st->nsyms; i++) {
		const struct nlist_64 *n = &syms[i];
		const char *name;
		size_t room;

		if ((n->n_type & N_STAB) || (n->n_type & N_TYPE) != N_SECT || !(n->n_type & N_EXT) ||
		    n->n_un.n_strx >= strsz) {
			continue;
		}
		name = strs + n->n_un.n_strx;
		room = strsz - n->n_un.n_strx;
		for (w = 0; w < nwant; w++) {
			size_t len = strlen(want[w].name);
			if (!want[w].found && len < room && memcmp(name, want[w].name, len + 1) == 0) {
				want[w].value = n->n_value;
				want[w].found = 1;
			}
		}
	}
	for (w = 0; w < nwant; w++) {
		if (!want[w].found) {
			err = fail(why, "a symbol is missing from the kernel file", ENOENT);
			goto done;
		}
	}
	err = 0;
done:
	if (strs != NULL) {
		m->free(strs, strsz);
	}
	if (syms != NULL) {
		m->free(syms, symsz);
	}
	m->free(hdr, hdralloc);
	return err;
}

int
rk_slide(const struct rk_sym *want, const uint64_t *live, unsigned nwant, uint64_t *slide, const char **why)
{
	unsigned i;
	int have = 0;
	uint64_t s = 0;

	for (i = 0; i < nwant; i++) {
		if (live[i] == 0) {
			continue;
		}
		if (!have) {
			s = live[i] - want[i].value;
			have = 1;
		} else if (live[i] - want[i].value != s) {
			return fail(why, "the kernel file is not the running kernel (symbols disagree on the slide)", ESRCH);
		}
	}
	/* platform: x86_64 KASLR slides by whole 4 KiB pages (2 MiB on xnu-2422) */
	if (!have || (s & 0xfff) != 0) {
		return fail(why, "slide not page aligned", ESRCH);
	}
	*slide = s;
	return 0;
}

int
rk_header_uuid(const void *hdr, uint8_t uuid[16])
{
	const struct mach_header_64 *mh = hdr;
	const uint8_t *lc, *end;
	uint32_t i;

	if (mh->magic != MH_MAGIC_64 || mh->cputype != CPU_TYPE_X86_64 || mh->filetype != MH_EXECUTE ||
	    mh->sizeofcmds > RK_LIVE_CMDS_CAP) {
		return ENOENT;
	}
	/* A-m2: bounded by sizeofcmds, never by ncmds alone */
	lc = (const uint8_t *)(mh + 1);
	end = lc + mh->sizeofcmds;
	for (i = 0; i < mh->ncmds; i++) {
		const struct load_command *c = (const struct load_command *)(const void *)lc;
		if ((size_t)(end - lc) < sizeof(*c) || c->cmdsize < sizeof(*c) || c->cmdsize > (size_t)(end - lc)) {
			return ENOENT;
		}
		if (c->cmd == LC_UUID) {
			if (c->cmdsize < sizeof(struct uuid_command)) {
				return ENOENT;
			}
			memcpy(uuid, ((const struct uuid_command *)(const void *)c)->uuid, 16);
			return 0;
		}
		lc += c->cmdsize;
	}
	return ENOENT;
}
