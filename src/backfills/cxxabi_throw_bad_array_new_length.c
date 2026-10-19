/*
 * __cxa_throw_bad_array_new_length (libc++abi, LLVM 13) -- custom polyfill (not from
 * macports-legacy-support).
 *
 * clang calls it when a new-expression's array bound is too small for its initializers.
 * Throws std::bad_array_new_length, whose constructor, destructor and type_info 10.9's
 * libc++abi exports; the object is the class's vtable pointer alone.
 */

#include <stddef.h>

extern void *__cxa_allocate_exception(size_t);
extern void __cxa_throw(void *, void *, void (*)(void *)) __attribute__((noreturn));
extern void recaulk_bad_array_new_length_ctor(void *) __asm__("__ZNSt20bad_array_new_lengthC1Ev");
extern void recaulk_bad_array_new_length_dtor(void *) __asm__("__ZNSt20bad_array_new_lengthD1Ev");
extern char recaulk_bad_array_new_length_ti __asm__("__ZTISt20bad_array_new_length");

void __cxa_throw_bad_array_new_length(void) {
  void *e = __cxa_allocate_exception(sizeof(void *));
  recaulk_bad_array_new_length_ctor(e);
  __cxa_throw(e, &recaulk_bad_array_new_length_ti, recaulk_bad_array_new_length_dtor);
}
