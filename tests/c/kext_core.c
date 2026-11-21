/* RecaulkKPI.kext's pure parts (src/kext/core.c) against well-formed and malformed kernel files, in userspace.
   With an argument (the 10.9 guest's /mach_kernel), it also reads the real kernel and checks its UUID against
   kern.uuid. */
#include <errno.h>
#include <fcntl.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <libkern/OSByteOrder.h>
#include "../../src/kext/core.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

/* ---- memory accounting ---- */
/* Each block ends flush against a PROT_NONE page, so a read past it faults; t_free checks the size it is given. */
static long live_allocs;
static size_t biggest_alloc;
static size_t span(size_t n) { size_t pg = (size_t)sysconf(_SC_PAGESIZE); return (n + pg - 1) / pg * pg + pg; }
static void *t_alloc(size_t n) {
	size_t pg = (size_t)sysconf(_SC_PAGESIZE), len = span(n);
	uint8_t *base = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
	if (base == MAP_FAILED) return NULL;
	if (mprotect(base + len - pg, pg, PROT_NONE) != 0) { munmap(base, len); return NULL; }
	live_allocs++;
	if (n > biggest_alloc) biggest_alloc = n;
	return base + len - pg - n;
}
static void t_free(void *p, size_t n) {
	size_t pg = (size_t)sysconf(_SC_PAGESIZE), len = span(n);
	uint8_t *base;
	if (p == NULL) return;
	base = (uint8_t *)p + n + pg - len;
	if (((uintptr_t)base & (pg - 1)) != 0) { fprintf(stderr, "FAIL: freed with a size it was not allocated with\n"); failures++; return; }
	live_allocs--;
	munmap(base, len);
}
static const struct rk_mem mem = { t_alloc, t_free };

/* ---- a file in a buffer ---- */
struct buf { const uint8_t *p; size_t n; };
static int buf_read(void *ctx, void *dst, size_t len, uint64_t off) {
	struct buf *b = ctx;
	if (off > b->n || len > b->n - off) return EIO;
	memcpy(dst, b->p + off, len);
	return 0;
}

/* ---- a synthetic kernel ---- */
#define TEXT_VM 0xffffff8000200000ULL
static const uint8_t UUID[16] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
static const char *const NAMES[] = { "_vnode_notify", "_printf", "_panic", "_vnode_isdir" };
static const uint64_t VALUES[] = { TEXT_VM + 0x1000, TEXT_VM + 0x2000, TEXT_VM + 0x3000, TEXT_VM + 0x4000 };
#define NNAMES 4

struct kfile { uint8_t *p; size_t n; struct symtab_command *st; struct load_command *last; struct mach_header_64 *mh; };

static struct kfile make_kernel(void) {
	struct kfile k;
	size_t cmds = sizeof(struct segment_command_64) + sizeof(struct uuid_command) + sizeof(struct symtab_command);
	size_t symoff = 4096, stroff, strsz = 1, i;
	struct segment_command_64 *seg;
	struct uuid_command *uc;
	struct nlist_64 *nl;
	for (i = 0; i < NNAMES; i++) strsz += strlen(NAMES[i]) + 1;
	stroff = symoff + NNAMES * sizeof(struct nlist_64);
	k.n = stroff + strsz;
	k.p = calloc(1, k.n);
	k.mh = (struct mach_header_64 *)k.p;
	k.mh->magic = MH_MAGIC_64; k.mh->cputype = CPU_TYPE_X86_64; k.mh->filetype = MH_EXECUTE;
	k.mh->ncmds = 3; k.mh->sizeofcmds = (uint32_t)cmds;
	seg = (struct segment_command_64 *)(k.mh + 1);
	seg->cmd = LC_SEGMENT_64; seg->cmdsize = sizeof *seg; strcpy(seg->segname, SEG_TEXT);
	seg->vmaddr = TEXT_VM; seg->vmsize = 0x100000; seg->fileoff = 0; seg->filesize = 4096;
	uc = (struct uuid_command *)(seg + 1);
	uc->cmd = LC_UUID; uc->cmdsize = sizeof *uc; memcpy(uc->uuid, UUID, 16);
	k.st = (struct symtab_command *)(uc + 1);
	k.st->cmd = LC_SYMTAB; k.st->cmdsize = sizeof *k.st;
	k.st->symoff = (uint32_t)symoff; k.st->nsyms = NNAMES; k.st->stroff = (uint32_t)stroff; k.st->strsize = (uint32_t)strsz;
	k.last = (struct load_command *)k.st;
	nl = (struct nlist_64 *)(k.p + symoff);
	{
		uint32_t at = 1;
		for (i = 0; i < NNAMES; i++) {
			nl[i].n_un.n_strx = at; nl[i].n_type = N_SECT | N_EXT; nl[i].n_sect = 1; nl[i].n_value = VALUES[i];
			strcpy((char *)k.p + stroff + at, NAMES[i]);
			at += (uint32_t)strlen(NAMES[i]) + 1;
		}
	}
	return k;
}

static int read_it(const uint8_t *p, size_t n, struct rk_kernel *out, struct rk_sym *want, const char **why) {
	struct buf b = { p, n };
	struct rk_file f = { &b, n, buf_read };
	unsigned i;
	for (i = 0; i < NNAMES; i++) { want[i].name = NAMES[i]; want[i].value = 0; want[i].found = 0; }
	biggest_alloc = 0;
	return rk_read_kernel(&f, &mem, out, want, NNAMES, why);
}

static void good(void) {
	struct kfile k = make_kernel();
	struct rk_kernel out; struct rk_sym want[NNAMES]; const char *why = NULL; unsigned i;
	int err = read_it(k.p, k.n, &out, want, &why);
	CHECK(err == 0);
	if (err) fprintf(stderr, "  good kernel: %s (%d)\n", why, err);
	CHECK(memcmp(out.uuid, UUID, 16) == 0);
	CHECK(out.text_vmaddr == TEXT_VM && out.text_vmsize == 0x100000);
	for (i = 0; i < NNAMES; i++) CHECK(want[i].found && want[i].value == VALUES[i]);
	CHECK(biggest_alloc <= k.n);
	CHECK(live_allocs == 0);
	free(k.p);
}

static void fat(void) {
	struct kfile k = make_kernel();
	size_t off = 4096, n = off + k.n;
	uint8_t *p = calloc(1, n);
	struct fat_header *fh = (struct fat_header *)p;
	struct fat_arch *fa = (struct fat_arch *)(fh + 1);
	struct rk_kernel out; struct rk_sym want[NNAMES]; const char *why = NULL;
	fh->magic = OSSwapHostToBigInt32(FAT_MAGIC); fh->nfat_arch = OSSwapHostToBigInt32(2);
	fa[0].cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_I386);
	fa[1].cputype = (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_X86_64);
	fa[1].offset = OSSwapHostToBigInt32((uint32_t)off); fa[1].size = OSSwapHostToBigInt32((uint32_t)k.n);
	memcpy(p + off, k.p, k.n);
	CHECK(read_it(p, n, &out, want, &why) == 0);
	CHECK(want[0].found && want[0].value == VALUES[0]);
	/* A slice that claims to run past the file. */
	fa[1].size = OSSwapHostToBigInt32((uint32_t)k.n + 1);
	CHECK(read_it(p, n, &out, want, &why) == EINVAL);
	CHECK(live_allocs == 0);
	free(p); free(k.p);
}

/* A-m1: a short LC_SYMTAB at the end of sizeofcmds; its later fields would lie past the commands. */
static void short_symtab(void) {
	struct kfile k = make_kernel();
	struct rk_kernel out; struct rk_sym want[NNAMES]; const char *why = NULL;
	k.st->cmdsize = 8;
	k.mh->sizeofcmds -= (uint32_t)(sizeof(struct symtab_command) - 8);
	CHECK(read_it(k.p, k.n, &out, want, &why) == EINVAL);
	CHECK(live_allocs == 0);
	free(k.p);
}

static void cmd_past_sizeofcmds(void) {
	struct kfile k = make_kernel();
	struct rk_kernel out; struct rk_sym want[NNAMES]; const char *why = NULL;
	k.last->cmdsize = 4096;
	CHECK(read_it(k.p, k.n, &out, want, &why) == EINVAL);
	k.last->cmdsize = sizeof(struct symtab_command);
	k.mh->sizeofcmds = RK_HEADER_READ;	/* claims more commands than the header read holds */
	CHECK(read_it(k.p, k.n, &out, want, &why) == EINVAL);
	CHECK(live_allocs == 0);
	free(k.p);
}

/* A-m5: tables that claim more than the file holds are refused before anything that size is allocated. */
static void tables_past_file(void) {
	struct kfile k = make_kernel();
	struct rk_kernel out; struct rk_sym want[NNAMES]; const char *why = NULL;
	k.st->nsyms = 1000000;	/* over the cap */
	CHECK(read_it(k.p, k.n, &out, want, &why) == EINVAL);
	CHECK(biggest_alloc <= k.n);
	k.st->nsyms = 100000;	/* under the cap, past the file */
	CHECK(read_it(k.p, k.n, &out, want, &why) == EINVAL);
	CHECK(biggest_alloc <= k.n);
	k.st->nsyms = NNAMES; k.st->strsize = 1u << 20;	/* under the cap, past the file */
	CHECK(read_it(k.p, k.n, &out, want, &why) == EINVAL);
	CHECK(biggest_alloc <= k.n);
	k.st->strsize = 16u << 20;
	CHECK(read_it(k.p, k.n, &out, want, &why) == EINVAL);
	CHECK(biggest_alloc <= k.n);
	k.st->strsize = 0;
	CHECK(read_it(k.p, k.n, &out, want, &why) == EINVAL);
	CHECK(live_allocs == 0);
	free(k.p);
}

static void strx_past_table(void) {
	struct kfile k = make_kernel();
	struct rk_kernel out; struct rk_sym want[NNAMES]; const char *why = NULL;
	struct nlist_64 *nl = (struct nlist_64 *)(k.p + k.st->symoff);
	uint32_t strsz = k.st->strsize;
	nl[0].n_un.n_strx = strsz;	/* _vnode_notify's name now lies past the string table */
	CHECK(read_it(k.p, k.n, &out, want, &why) == ENOENT);
	CHECK(!want[0].found);
	/* The table ends "_vnode_no" with no NUL: a match must not read past its end. */
	memcpy(k.p + k.st->stroff + strsz - 9, "_vnode_no", 9);
	nl[0].n_un.n_strx = strsz - 9;
	CHECK(read_it(k.p, k.n, &out, want, &why) == ENOENT);
	CHECK(!want[0].found);
	CHECK(live_allocs == 0);
	free(k.p);
}

static void not_a_kernel(void) {
	struct kfile k = make_kernel();
	struct rk_kernel out; struct rk_sym want[NNAMES]; const char *why = NULL;
	k.mh->filetype = MH_DYLIB;
	CHECK(read_it(k.p, k.n, &out, want, &why) == EINVAL);
	CHECK(read_it(k.p, 16, &out, want, &why) != 0);	/* shorter than a header */
	CHECK(live_allocs == 0);
	free(k.p);
}

static void slide(void) {
	struct rk_sym want[NNAMES]; uint64_t live[NNAMES], s = 0; const char *why = NULL; unsigned i;
	for (i = 0; i < NNAMES; i++) { want[i].name = NAMES[i]; want[i].value = VALUES[i]; want[i].found = 1; live[i] = VALUES[i] + 0x2a00000; }
	live[0] = 0;	/* the one to resolve */
	CHECK(rk_slide(want, live, NNAMES, &s, &why) == 0 && s == 0x2a00000);
	live[3] += 0x1000;
	CHECK(rk_slide(want, live, NNAMES, &s, &why) == ESRCH);
	for (i = 1; i < NNAMES; i++) live[i] = VALUES[i] + 0x2a00010;
	CHECK(rk_slide(want, live, NNAMES, &s, &why) == ESRCH);
}

/* review M1: before the live header is read, every live symbol lies in the file's __TEXT moved by the slide, so a
   wrong but agreeing slide never sends rk_header_uuid to an arbitrary kernel address */
static void live_in_text(void) {
	struct rk_kernel k; uint64_t live[NNAMES]; const char *why = NULL; unsigned i;
	memset(&k, 0, sizeof k);
	k.text_vmaddr = TEXT_VM; k.text_vmsize = 0x10000;
	for (i = 0; i < NNAMES; i++) live[i] = VALUES[i] + 0x2a00000;
	live[0] = 0;
	CHECK(rk_live_in_text(&k, live, NNAMES, 0x2a00000, &why) == 0);
	CHECK(rk_live_in_text(&k, live, NNAMES, 0x2b00000, &why) == ESRCH);
	live[2] = TEXT_VM + 0x2a00000 + 0x10000;	/* one past the end */
	CHECK(rk_live_in_text(&k, live, NNAMES, 0x2a00000, &why) == ESRCH);
}

/* A-m2: the in-memory walk stops at sizeofcmds; a guard page after the header catches any read past it. */
static void live_header(void) {
	long pg = sysconf(_SC_PAGESIZE);
	uint8_t *map = mmap(NULL, (size_t)pg * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
	size_t cmds = sizeof(struct segment_command_64) + sizeof(struct uuid_command);
	struct mach_header_64 *mh;
	struct segment_command_64 *seg;
	struct uuid_command *uc;
	uint8_t got[16];
	CHECK(map != MAP_FAILED);
	if (map == MAP_FAILED) return;
	CHECK(mprotect(map + pg, (size_t)pg, PROT_NONE) == 0);
	mh = (struct mach_header_64 *)(map + pg - sizeof *mh - cmds);
	mh->magic = MH_MAGIC_64; mh->cputype = CPU_TYPE_X86_64; mh->filetype = MH_EXECUTE;
	mh->ncmds = 2; mh->sizeofcmds = (uint32_t)cmds;
	seg = (struct segment_command_64 *)(mh + 1); seg->cmd = LC_SEGMENT_64; seg->cmdsize = sizeof *seg;
	uc = (struct uuid_command *)(seg + 1); uc->cmd = LC_UUID; uc->cmdsize = sizeof *uc; memcpy(uc->uuid, UUID, 16);
	CHECK(rk_header_uuid(mh, got) == 0 && memcmp(got, UUID, 16) == 0);
	mh->ncmds = 50;	/* more commands claimed than sizeofcmds holds: stop at the guard page, not past it */
	uc->cmd = LC_SEGMENT_64;
	CHECK(rk_header_uuid(mh, got) != 0);
	mh->ncmds = 2; uc->cmd = LC_UUID;
	seg->cmdsize = 0x7ffffff0;	/* a huge step */
	CHECK(rk_header_uuid(mh, got) != 0);
	seg->cmdsize = 4;		/* a step too small to be a command */
	CHECK(rk_header_uuid(mh, got) != 0);
	seg->cmdsize = sizeof *seg; uc->cmdsize = 8;	/* a short LC_UUID */
	CHECK(rk_header_uuid(mh, got) != 0);
	munmap(map, (size_t)pg * 2);
}

static void gate(void) {
	CHECK(rk_kernel_supported(13));
	CHECK(!rk_kernel_supported(12));
	CHECK(!rk_kernel_supported(14));
	CHECK(!rk_kernel_supported(23));
}

/* ---- the real kernel, on 10.9 ---- */
static int fd_read(void *ctx, void *dst, size_t len, uint64_t off) {
	ssize_t r = pread(*(int *)ctx, dst, len, (off_t)off);
	return r == (ssize_t)len ? 0 : EIO;
}

static void real_kernel(const char *path) {
	int fd = open(path, O_RDONLY);
	struct stat sb;
	struct rk_kernel out; struct rk_sym want[NNAMES]; const char *why = NULL; unsigned i;
	char uuid[64] = "", mine[64];
	size_t ul = sizeof uuid;
	CHECK(fd >= 0 && fstat(fd, &sb) == 0);
	if (fd < 0) return;
	{
		struct rk_file f = { &fd, (uint64_t)sb.st_size, fd_read };
		for (i = 0; i < NNAMES; i++) { want[i].name = NAMES[i]; want[i].found = 0; }
		CHECK(rk_read_kernel(&f, &mem, &out, want, NNAMES, &why) == 0);
	}
	for (i = 0; i < NNAMES; i++) CHECK(want[i].found);
	CHECK(sysctlbyname("kern.uuid", uuid, &ul, NULL, 0) == 0);
	snprintf(mine, sizeof mine, "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
	    out.uuid[0], out.uuid[1], out.uuid[2], out.uuid[3], out.uuid[4], out.uuid[5], out.uuid[6], out.uuid[7],
	    out.uuid[8], out.uuid[9], out.uuid[10], out.uuid[11], out.uuid[12], out.uuid[13], out.uuid[14], out.uuid[15]);
	CHECK(strcmp(uuid, mine) == 0);
	if (strcmp(uuid, mine) != 0) fprintf(stderr, "  kern.uuid %s, %s's %s\n", uuid, path, mine);
	CHECK(live_allocs == 0);
	close(fd);
}

int main(int argc, char **argv) {
	gate();
	good();
	fat();
	short_symtab();
	cmd_past_sizeofcmds();
	tables_past_file();
	strx_past_table();
	not_a_kernel();
	slide();
	live_in_text();
	live_header();
	if (argc > 1) real_kernel(argv[1]);
	if (failures) return 1;
	printf("kext_core: ok\n");
	return 0;
}
