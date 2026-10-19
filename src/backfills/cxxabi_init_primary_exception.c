/*
 * __cxa_init_primary_exception (libc++abi, LLVM 18) -- custom polyfill (not from
 * macports-legacy-support).
 *
 * std::make_exception_ptr calls it on memory from __cxa_allocate_exception, to make an
 * exception that is never thrown but can be rethrown. It fills in the header libc++abi
 * keeps just before the thrown object, as libc++abi's own does.
 *
 * Only the header's tail is written, referenceCount through unwindHeader. That tail sits
 * immediately before the object in every Apple libc++abi: when LLVM padded the header to
 * 16 bytes it put the padding at the front for exactly this reason, so 10.9's header
 * (without it) and later ones (with it) agree on every offset counted back from the object.
 */

#include <stddef.h>
#include <stdint.h>

struct recaulk_unwind_exception {
  uint64_t exception_class;
  void (*exception_cleanup)(int, struct recaulk_unwind_exception *);
  uintptr_t private_1, private_2;
};
struct recaulk_cxa_exception_tail {
  size_t referenceCount;
  void *exceptionType;
  void (*exceptionDestructor)(void *);
  void (*unexpectedHandler)(void);
  void (*terminateHandler)(void);
  void *nextException;
  int handlerCount, handlerSwitchValue;
  const unsigned char *actionRecord, *languageSpecificData;
  void *catchTemp, *adjustedPtr;
  struct recaulk_unwind_exception unwindHeader;
};
_Static_assert(sizeof(struct recaulk_cxa_exception_tail) == 120, "the x86_64 __cxa_exception tail");

extern void (*recaulk_std_get_unexpected(void))(void) __asm__("__ZSt14get_unexpectedv");
extern void (*recaulk_std_get_terminate(void))(void) __asm__("__ZSt13get_terminatev");
extern void recaulk_std_terminate(void) __asm__("__ZSt9terminatev") __attribute__((noreturn));
extern void __cxa_decrement_exception_refcount(void *);

/* "CLNGC++\0": libc++abi's own exception class, so its personality routine claims it. */
#define RECAULK_CLANG_CXX_EXCEPTION_CLASS 0x434C4E47432B2B00ULL
/* _URC_FOREIGN_EXCEPTION_CAUGHT: the one reason another runtime may delete our exception. */
#define RECAULK_URC_FOREIGN_EXCEPTION_CAUGHT 1

static void cleanup(int reason, struct recaulk_unwind_exception *u) {
  struct recaulk_cxa_exception_tail *t =
      (struct recaulk_cxa_exception_tail *)((char *)(u + 1) - sizeof(struct recaulk_cxa_exception_tail));
  if (reason != RECAULK_URC_FOREIGN_EXCEPTION_CAUGHT) {
    if (t->terminateHandler) t->terminateHandler();
    recaulk_std_terminate();
  }
  __cxa_decrement_exception_refcount(u + 1);
}

/* Returns the header libc++'s declaration names; libc++ ignores it, so the tail's start serves. */
void *__cxa_init_primary_exception(void *object, void *tinfo, void (*dest)(void *)) {
  struct recaulk_cxa_exception_tail *t =
      (struct recaulk_cxa_exception_tail *)((char *)object - sizeof(struct recaulk_cxa_exception_tail));
  t->referenceCount = 0;
  t->unexpectedHandler = recaulk_std_get_unexpected();
  t->terminateHandler = recaulk_std_get_terminate();
  t->exceptionType = tinfo;
  t->exceptionDestructor = dest;
  t->unwindHeader.exception_class = RECAULK_CLANG_CXX_EXCEPTION_CLASS;
  t->unwindHeader.exception_cleanup = cleanup;
  return t;
}
