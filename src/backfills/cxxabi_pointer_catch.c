/*
 * Catch rules for pointer and pointer-to-member handlers, as LLVM 22's libc++abi gives them, in the
 * image that links this (10.9's libc++abi catches a thrown nullptr as no member pointer, an int** as
 * no const int* const*, and a null derived pointer as a non-null base pointer) -- custom polyfill (not
 * from macports-legacy-support).
 *
 * The system's personality routine asks the HANDLER's type_info whether it can catch the thrown
 * type, through slot 4 of its vtable (can_catch). The type_info clang emits for a pointer or member
 * pointer type points at __cxxabiv1::__pointer_type_info's (or __pointer_to_member_type_info's)
 * vtable by symbol, so an image that defines those vtables itself has its own handlers' questions
 * answered by this code, with the system's runtime, and its exception state, otherwise untouched.
 * Each vtable's type_info slot is the SYSTEM's type_info for the class: the system tells kinds of
 * type_info apart by that, so it still knows these for what they are.
 *
 * HIDDEN, deliberately: these replace the system's vtables only inside the image that links them,
 * and other images, the system's own libraries among them, keep the system's rules. Both names are
 * 10.9 exports, so build/image-local-shadows.txt declares them, rule 1's one exception. Left as the
 * system has it: catch (void *) of a function pointer, since void*'s type_info is the system's.
 *
 * Built a second time with RECAULK_CXXABI_EXPORTS, public, into librecaulk-cxxabi-exports.a and never
 * into librecaulk.a: for libcxx22's libc++abi.1.dylib, its one consumer, to export, so every program
 * that reaches the C++ ABI through libcxx22 gets these rules too.
 *
 * Ported from LLVM 22's libcxxabi/src/private_typeinfo.cpp: throw nullptr caught as a pointer or
 * member pointer, noexcept function pointers caught as plain ones, multi-level qualification
 * conversions, pointers to incomplete classes compared by name, and a null derived pointer caught
 * as a base pointer staying null. The base-class walk is its own, without an object where it has
 * none, rather than 10.9's, whose info struct is older and which reads through a null object.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

struct ti { const void *const *vptr; const char *name; };
struct pbase { struct ti ti; unsigned int flags; const struct ti *pointee; };
struct ptm { struct pbase pb; const struct ti *context; };
struct si { struct ti ti; const struct ti *base; };
struct base_info { const struct ti *base; long offset_flags; };
struct vmi { struct ti ti; unsigned int flags; unsigned int base_count; struct base_info base_info[1]; };

enum { const_mask = 0x1, volatile_mask = 0x2, restrict_mask = 0x4, incomplete_mask = 0x8,
       incomplete_class_mask = 0x10, transaction_safe_mask = 0x20, noexcept_mask = 0x40,
       no_remove_flags_mask = const_mask | volatile_mask | restrict_mask,
       no_add_flags_mask = transaction_safe_mask | noexcept_mask };
enum { virtual_mask = 0x1, public_mask = 0x2, offset_shift = 8 };
enum { unknown_path, public_path, not_public_path };

#define SYS(var, sym) extern const struct ti var __asm__(sym)
SYS(ti_class, "__ZTIN10__cxxabiv117__class_type_infoE");
SYS(ti_si, "__ZTIN10__cxxabiv120__si_class_type_infoE");
SYS(ti_vmi, "__ZTIN10__cxxabiv121__vmi_class_type_infoE");
SYS(ti_pointer, "__ZTIN10__cxxabiv119__pointer_type_infoE");
SYS(ti_ptm, "__ZTIN10__cxxabiv129__pointer_to_member_type_infoE");
SYS(ti_function, "__ZTIN10__cxxabiv120__function_type_infoE");
SYS(ti_nullptr, "__ZTIDn");
SYS(ti_void, "__ZTIv");

/* The class of a type_info: its vtable's type_info slot, the system's either way. */
static const struct ti *kind(const struct ti *t) { return (const struct ti *)t->vptr[-1]; }
static bool is_class(const struct ti *t) {
  const struct ti *k = kind(t);
  return k == &ti_class || k == &ti_si || k == &ti_vmi;
}
static bool same(const struct ti *x, const struct ti *y, bool by_name) {
  return x == y || (by_name && strcmp(x->name, y->name) == 0);
}

struct walk { const struct ti *target; void *found; const void *found_vbase; const void *vbase;
              int path, count; bool have_object, done; };

static void found_base(struct walk *w, void *p, int path) {
  if (w->count == 0) {
    w->found = p; w->path = path; w->found_vbase = w->vbase; w->count = 1;
  } else if (w->found_vbase == w->vbase && w->found == p) {
    if (w->path == not_public_path) w->path = path;   /* the same subobject: keep the most public path */
  } else {
    w->count++; w->path = not_public_path; w->done = true;   /* ambiguous */
  }
}

static void find_base(struct walk *w, const struct ti *c, void *p, int path);

static void through_base(struct walk *w, const struct base_info *b, void *p, int path) {
  bool is_virtual = b->offset_flags & virtual_mask;
  ptrdiff_t off = b->offset_flags >> offset_shift;
  const void *saved = w->vbase;
  if (w->have_object) {
    if (is_virtual) off = *(const ptrdiff_t *)(*(const char *const *)p + off);
  } else if (is_virtual) {
    w->vbase = b->base->name; p = NULL; off = 0;   /* no object to find a virtual base's offset in */
  }
  find_base(w, b->base, (char *)p + off, (b->offset_flags & public_mask) ? path : not_public_path);
  w->vbase = saved;
}

static void find_base(struct walk *w, const struct ti *c, void *p, int path) {
  const struct ti *k = kind(c);
  if (c == w->target) { found_base(w, p, path); return; }
  if (k == &ti_si) {
    struct base_info b = { ((const struct si *)c)->base, public_mask };
    through_base(w, &b, p, path);
  } else if (k == &ti_vmi) {
    const struct vmi *v = (const struct vmi *)c;
    for (unsigned int i = 0; i < v->base_count && !w->done; i++) through_base(w, &v->base_info[i], p, path);
  }
}

static bool ptm_can_catch_nested(const struct ptm *self, const struct ti *thrown) {
  const struct ptm *t = (const struct ptm *)thrown;
  if (kind(thrown) != &ti_ptm) return false;
  if (~self->pb.flags & t->pb.flags) return false;
  return same(self->pb.pointee, t->pb.pointee, false) && same(self->context, t->context, false);
}

static bool pointer_can_catch_nested(const struct pbase *self, const struct ti *thrown) {
  const struct pbase *t = (const struct pbase *)thrown;
  if (kind(thrown) != &ti_pointer) return false;
  if (t->flags & ~self->flags) return false;
  if (same(self->pointee, t->pointee, false)) return true;
  if (~self->flags & const_mask) return false;   /* differing pointees need a const catch */
  if (kind(self->pointee) == &ti_pointer)
    return pointer_can_catch_nested((const struct pbase *)self->pointee, t->pointee);
  if (kind(self->pointee) == &ti_ptm)
    return ptm_can_catch_nested((const struct ptm *)self->pointee, t->pointee);
  return false;
}

/* Bullet 1 for both: the same type, by name where either side is incomplete. */
static bool pbase_same(const struct pbase *self, const struct ti *thrown) {
  bool by_name = self->flags & (incomplete_class_mask | incomplete_mask);
  if (!by_name) {
    const struct ti *k = kind(thrown);
    if (k != &ti_pointer && k != &ti_ptm) return false;
    by_name = ((const struct pbase *)thrown)->flags & (incomplete_class_mask | incomplete_mask);
  }
  return same(&self->ti, thrown, by_name);
}

static bool pointer_can_catch(const struct pbase *self, const struct ti *thrown, void **adj) {
  const struct pbase *t = (const struct pbase *)thrown;
  if (thrown == &ti_nullptr) { *adj = NULL; return true; }
  if (pbase_same(self, thrown)) {
    if (*adj) *adj = *(void **)*adj;
    return true;
  }
  if (kind(thrown) != &ti_pointer) return false;
  if (*adj) *adj = *(void **)*adj;
  if (t->flags & ~self->flags & no_remove_flags_mask) return false;
  if (self->flags & ~t->flags & no_add_flags_mask) return false;
  if (same(self->pointee, t->pointee, false)) return true;
  if (self->pointee == &ti_void) return kind(t->pointee) != &ti_function;   /* no function to void* */
  if (kind(self->pointee) == &ti_pointer) {
    if (~self->flags & const_mask) return false;
    return pointer_can_catch_nested((const struct pbase *)self->pointee, t->pointee);
  }
  if (kind(self->pointee) == &ti_ptm) {
    if (~self->flags & const_mask) return false;
    return ptm_can_catch_nested((const struct ptm *)self->pointee, t->pointee);
  }
  if (!is_class(self->pointee) || !is_class(t->pointee)) return false;
  struct walk w = { self->pointee, NULL, NULL, NULL, unknown_path, 0, *adj != NULL, false };
  find_base(&w, t->pointee, *adj, public_path);
  if (w.path != public_path) return false;
  *adj = w.have_object ? w.found : NULL;   /* a null pointer is caught as null, not as its base's offset */
  return true;
}

static bool ptm_can_catch(const struct ptm *self, const struct ti *thrown, void **adj) {
  const struct ptm *t = (const struct ptm *)thrown;
  if (thrown == &ti_nullptr) {
    /* One null representation each for data and function member pointers. */
    static const ptrdiff_t null_data = -1;
    static const struct { void *fn; ptrdiff_t adj; } null_fn = { NULL, 0 };
    *adj = kind(self->pb.pointee) == &ti_function ? (void *)&null_fn : (void *)&null_data;
    return true;
  }
  if (pbase_same(&self->pb, thrown)) return true;
  if (kind(thrown) != &ti_ptm) return false;
  if (t->pb.flags & ~self->pb.flags & no_remove_flags_mask) return false;
  if (self->pb.flags & ~t->pb.flags & no_add_flags_mask) return false;
  return same(self->pb.pointee, t->pb.pointee, false) && same(self->context, t->context, false);
}

static void nothing(const struct ti *self) { (void)self; }

#ifdef RECAULK_CXXABI_EXPORTS
#define RECAULK_VTABLE_VISIBILITY "default"
#else
#define RECAULK_VTABLE_VISIBILITY "hidden"
#endif
#define RECAULK_VTABLE(var, sym) \
  __attribute__((visibility(RECAULK_VTABLE_VISIBILITY), used)) const void *const var[7] __asm__(sym)
RECAULK_VTABLE(recaulk_pointer_vt, "__ZTVN10__cxxabiv119__pointer_type_infoE") =
  { NULL, &ti_pointer, (const void *)nothing, (const void *)nothing, (const void *)nothing,
    (const void *)nothing, (const void *)pointer_can_catch };
RECAULK_VTABLE(recaulk_ptm_vt, "__ZTVN10__cxxabiv129__pointer_to_member_type_infoE") =
  { NULL, &ti_ptm, (const void *)nothing, (const void *)nothing, (const void *)nothing,
    (const void *)nothing, (const void *)ptm_can_catch };
