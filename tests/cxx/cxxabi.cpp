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

// Catch rules for pointer and member-pointer handlers, as the standard and a current libc++abi give
// them. 10.9's catches a thrown nullptr as no data member pointer, an int** as no const int* const*,
// and a null D* as a non-null B2*; src/backfills/cxxabi_pointer_catch.c gives these the rules.
struct M { int d; void f() {} };
struct B1 { int a; };
struct B2 { int b; };
struct D : B1, B2 { int c; };
struct V : virtual B2 { int v; };
struct VD : V { int w; };
struct P : private B2 { int p; };
struct A1 : B1 {};
struct A2 : B1 {};
struct Amb : A1, A2 {};

static bool nullptr_as_pointer(void) {
  try { throw nullptr; } catch (int *p) { return p == 0; } catch (...) {}
  return false;
}
static bool nullptr_as_data_member_pointer(void) {
  try { throw nullptr; } catch (int M::*p) { return p == 0; } catch (...) {}
  return false;
}
static bool nullptr_as_function_member_pointer(void) {
  try { throw nullptr; } catch (void (M::*p)()) { return p == 0; } catch (...) {}
  return false;
}
static bool multi_level_qualified(int **p) {
  try { throw p; } catch (const int *const *q) { return q == p; } catch (...) {}
  return false;
}
static bool null_derived_as_base(void) {  // a null pointer converts to null, not to the base's offset
  try { throw static_cast<D *>(0); } catch (B2 *q) { return q == 0; } catch (...) {}
  return false;
}
static bool multi_level_unsafe_refused(int **p) {  // int** to const int** would open a hole in const
  try { throw p; } catch (const int **) { return false; } catch (...) { return true; }
}
static bool three_level_unsafe_refused(int ***p) {  // const must be added at every level below the top
  try { throw p; } catch (const int **const *) { return false; } catch (...) { return true; }
}
static bool derived_as_base(D *p) {
  try { throw p; } catch (B2 *q) { return q == static_cast<B2 *>(p); } catch (...) {}
  return false;
}
static bool derived_as_virtual_base(VD *p) {
  try { throw p; } catch (B2 *q) { return q == static_cast<B2 *>(p); } catch (...) {}
  return false;
}
static bool private_base_refused(P *p) {
  try { throw p; } catch (B2 *) { return false; } catch (...) { return true; }
}
static bool ambiguous_base_refused(Amb *p) {
  try { throw p; } catch (B1 *) { return false; } catch (...) { return true; }
}
static bool object_as_void_pointer(int *p) {
  try { throw p; } catch (void *q) { return q == p; } catch (...) {}
  return false;
}
static bool member_pointer_exact(int M::*p) {
  try { throw p; } catch (int M::*q) { return q == p; } catch (...) {}
  return false;
}
#ifdef __cpp_noexcept_function_type
static void noexcept_fn() noexcept {}
static bool noexcept_as_plain_function_pointer(void) {
  try { throw &noexcept_fn; } catch (void (*q)()) { return q == &noexcept_fn; } catch (...) {}
  return false;
}
#endif

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

  // pointer and member-pointer handlers
  static int i = 7;
  static int *pi = &i;
  static D d;
  static VD vd;
  static P pr;
  static Amb amb;
  check("catch-nullptr-pointer", nullptr_as_pointer(), "a thrown nullptr was not caught as a null int*");
  check("catch-nullptr-data-member", nullptr_as_data_member_pointer(), "a thrown nullptr was not caught as a null int M::*");
  check("catch-nullptr-function-member", nullptr_as_function_member_pointer(), "a thrown nullptr was not caught as a null void (M::*)()");
  check("catch-multi-level-qualified", multi_level_qualified(&pi), "a thrown int** was not caught as const int* const*");
  check("catch-null-derived-as-base", null_derived_as_base(), "a thrown null D* was caught as a non-null B2*, or not at all");
  check("catch-multi-level-unsafe", multi_level_unsafe_refused(&pi), "a thrown int** was caught as const int**");
  static int **ppi = &pi;
  check("catch-three-level-unsafe", three_level_unsafe_refused(&ppi), "a thrown int*** was caught as const int** const*");
  check("catch-derived-as-base", derived_as_base(&d), "a thrown D* was not caught as its B2* subobject");
  check("catch-derived-as-virtual-base", derived_as_virtual_base(&vd), "a thrown VD* was not caught as its virtual B2* subobject");
  check("catch-private-base", private_base_refused(&pr), "a thrown P* was caught as its private base");
  check("catch-ambiguous-base", ambiguous_base_refused(&amb), "a thrown Amb* was caught as its ambiguous base");
  check("catch-void-pointer", object_as_void_pointer(&i), "a thrown int* was not caught as void*");
  check("catch-member-pointer", member_pointer_exact(&M::d), "a thrown int M::* was not caught as one");
#ifdef __cpp_noexcept_function_type
  check("catch-noexcept-function-pointer", noexcept_as_plain_function_pointer(), "a thrown noexcept function pointer was not caught as a plain one");
#endif
  return failed;
}
