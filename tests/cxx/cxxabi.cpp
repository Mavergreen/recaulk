// The libc++abi back-fills, each through the call libc++ or clang makes to reach it. C++11, so 10.9's
// Apple clang builds it too; char8_t and __float128 are checked where the compiler has them. Prints
// one "PASS name" or "FAIL name: why" per check; exits non-zero on any FAIL.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <new>
#include <typeinfo>
#include <sys/wait.h>
#include <unistd.h>

// Declared under local names bound to the ABI symbols: libc++'s headers declare some of these
// themselves, with types that differ between versions.
extern "C" {
unsigned int t_uncaught_exceptions(void) throw() __asm__("___cxa_uncaught_exceptions");
void t_throw_bad_array_new_length(void) __asm__("___cxa_throw_bad_array_new_length");
void t_call_terminate(void *) throw() __asm__("___cxa_call_terminate");
void *t_allocate_exception(size_t) throw() __asm__("___cxa_allocate_exception");
void *t_init_primary_exception(void *, std::type_info *, void (*)(void *)) throw() __asm__("___cxa_init_primary_exception");
void t_increment_exception_refcount(void *) throw() __asm__("___cxa_increment_exception_refcount");
void t_decrement_exception_refcount(void *) throw() __asm__("___cxa_decrement_exception_refcount");
void t_rethrow_primary_exception(void *) __asm__("___cxa_rethrow_primary_exception");
}

static int failed = 0;
static void check(const char *name, bool ok, const char *why) {
  if (ok) std::printf("PASS %s\n", name);
  else { std::printf("FAIL %s: %s\n", name, why); failed = 1; }
}

static unsigned int seen_in_dtor = 99;
struct Peek { ~Peek() { seen_in_dtor = t_uncaught_exceptions(); } };

static int freed = 0;
static void dest(void *) { freed++; }

static void exit_42(void) { _exit(42); }

template <class T> static bool caught_as_pointer(T *p) {
  try { throw p; } catch (T *q) { return q == p; } catch (...) {}
  return false;
}
template <class T> static bool const_kept(const T *p) {  // const may not be dropped: __flags at work
  try { throw p; } catch (T *) { return false; } catch (const T *q) { return q == p; } catch (...) {}
  return false;
}
template <class T> static bool caught_as_const_pointer(T *p) {
  try { throw p; } catch (const T *q) { return q == p; } catch (...) {}  // qualification conversion
  return false;
}

int main(void) {
  // std::uncaught_exceptions()
  check("uncaught_exceptions-idle", t_uncaught_exceptions() == 0, "nonzero with nothing in flight");
  try { Peek p; throw 1; } catch (int) {}
  check("uncaught_exceptions-unwinding", seen_in_dtor == 1, "not 1 in a destructor run by unwinding");
  check("uncaught_exceptions-after", t_uncaught_exceptions() == 0, "nonzero after the handler");

  // new T[n]{...} with too few elements
  bool typed = false;
  try { t_throw_bad_array_new_length(); }
  catch (const std::bad_array_new_length &e) { typed = e.what() != 0; } catch (...) {}
  check("throw_bad_array_new_length", typed, "did not throw a std::bad_array_new_length");

  // std::make_exception_ptr: allocate, initialise, hold a reference, rethrow, release
  void *o = t_allocate_exception(sizeof(int));
  *static_cast<int *>(o) = 42;
  t_init_primary_exception(o, const_cast<std::type_info *>(&typeid(int)), dest);
  t_increment_exception_refcount(o);
  int got = 0;
  try { t_rethrow_primary_exception(o); } catch (int v) { got = v; } catch (...) { got = -1; }
  check("init_primary_exception-rethrown", got == 42, got == -1 ? "rethrown, but not caught as int" : "not rethrown");
  check("init_primary_exception-held", freed == 0, "destroyed while a reference was still held");
  t_decrement_exception_refcount(o);
  check("init_primary_exception-released", freed == 1, "the last release did not run the destructor once");

  // a noexcept function's cleanup: begin the catch, then terminate
  pid_t pid = fork();
  if (pid == 0) {
    std::set_terminate(exit_42);
    void *e = t_allocate_exception(sizeof(int));
    t_init_primary_exception(e, const_cast<std::type_info *>(&typeid(int)), 0);
    t_call_terminate(static_cast<char *>(e) - 32);  // the _Unwind_Exception just before the object
    _exit(1);
  }
  int st = 0;
  waitpid(pid, &st, 0);
  check("call_terminate", WIFEXITED(st) && WEXITSTATUS(st) == 42, "did not reach the terminate handler");

  // type_info the compiler references and expects the ABI library to define
  check("typeinfo-int128-name", !std::strcmp(typeid(__int128).name(), "n"), typeid(__int128).name());
  check("typeinfo-uint128-name", !std::strcmp(typeid(unsigned __int128).name(), "o"), typeid(unsigned __int128).name());
  static __int128 x = 5;
  static unsigned __int128 ux = 6;
  check("typeinfo-int128-pointer", caught_as_pointer(&x), "a thrown __int128* was not caught as one");
  check("typeinfo-int128-const-pointer", caught_as_const_pointer(&x), "a thrown __int128* was not caught as const __int128*");
  check("typeinfo-uint128-pointer", caught_as_pointer(&ux), "a thrown unsigned __int128* was not caught as one");
  check("typeinfo-int128-const-kept", const_kept(static_cast<const __int128 *>(&x)), "a thrown const __int128* was caught as __int128*, or not at all");
#ifdef __cpp_char8_t
  static char8_t c8 = 'x';
  check("typeinfo-char8_t-name", !std::strcmp(typeid(char8_t).name(), "Du"), typeid(char8_t).name());
  check("typeinfo-char8_t-const-pointer", caught_as_const_pointer(&c8), "a thrown char8_t* was not caught as const char8_t*");
#endif
#ifdef __SIZEOF_FLOAT128__
  check("typeinfo-float128-name", !std::strcmp(typeid(__float128).name(), "g"), typeid(__float128).name());
#endif
  return failed;
}
