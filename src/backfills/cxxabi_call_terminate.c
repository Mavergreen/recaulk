/*
 * __cxa_call_terminate (libc++abi, LLVM 18) -- custom polyfill (not from
 * macports-legacy-support).
 *
 * clang 18 and later call it from the landing pad that ends a noexcept function an
 * exception escapes: begin the catch, so the terminate handler sees the exception as
 * current, then terminate. As libc++abi's own.
 */

extern void *__cxa_begin_catch(void *);
extern void recaulk_std_terminate(void) __asm__("__ZSt9terminatev") __attribute__((noreturn));

void __cxa_call_terminate(void *unwind_arg) {
  __cxa_begin_catch(unwind_arg);
  recaulk_std_terminate();
}
