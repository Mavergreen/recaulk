/*
 * __cxa_uncaught_exceptions (libc++abi, macOS 10.12+) -- custom polyfill (not from
 * macports-legacy-support).
 *
 * std::uncaught_exceptions() calls it. 10.9's libc++abi keeps the same count, in the
 * per-thread globals __cxa_get_globals() returns, and exposes it only through the bool
 * __cxa_uncaught_exception(); this reads the count itself. The globals' first two
 * fields have kept this layout in every libc++abi.
 */

struct recaulk_cxa_eh_globals { void *caughtExceptions; unsigned int uncaughtExceptions; };
extern struct recaulk_cxa_eh_globals *__cxa_get_globals(void);

unsigned int __cxa_uncaught_exceptions(void) {
  return __cxa_get_globals()->uncaughtExceptions;
}
