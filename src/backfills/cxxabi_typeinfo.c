/*
 * type_info for _Float16 (Dh), char8_t (Du), __float128 (g), __int128 (n) and
 * unsigned __int128 (o), and for pointers and const pointers to each (libc++abi; 10.9's
 * lacks them) -- custom polyfill (not from macports-legacy-support).
 *
 * The compiler never emits type_info for a fundamental type: it references the ABI
 * library's, so catching, typeid and dynamic_cast on these types would not link. These
 * are laid out as libc++abi's own (__fundamental_type_info; __pointer_type_info with
 * __flags and __pointee), using the vtables 10.9 exports.
 *
 * WEAK, deliberately, unlike Recaulk's other data. A consumer defining one of these keeps
 * its own without a duplicate-symbol error, and all thirty can live in one member
 * (spec, one back-fill per member). The cost: type_info compares by address, so on a
 * macOS whose libc++abi defines these too, an exception of one of these types thrown in
 * the system's code and caught in ours (or the reverse) does not match its handler.
 */

struct recaulk_type_info { const void *vtable; const char *name; };
struct recaulk_pointer_type_info { const void *vtable; const char *name; unsigned int flags; const void *pointee; };

extern const char recaulk_fundamental_vt[] __asm__("__ZTVN10__cxxabiv123__fundamental_type_infoE");
extern const char recaulk_pointer_vt[] __asm__("__ZTVN10__cxxabiv119__pointer_type_infoE");

/* The address point: a vtable's first two words are the offset-to-top and the type_info pointer. */
#define RECAULK_VT(vt) ((vt) + 2 * sizeof(void *))
/* __pbase_type_info::__const_mask */
#define RECAULK_CONST_MASK 0x1

#define RECAULK_FUNDAMENTAL(code)                                                                 \
  __attribute__((weak)) const char recaulk_ts_##code[] __asm__("__ZTS" #code) = #code;             \
  __attribute__((weak)) const struct recaulk_type_info recaulk_ti_##code __asm__("__ZTI" #code) = \
      {RECAULK_VT(recaulk_fundamental_vt), recaulk_ts_##code};                                    \
  __attribute__((weak)) const char recaulk_ts_P##code[] __asm__("__ZTSP" #code) = "P" #code;       \
  __attribute__((weak)) const struct recaulk_pointer_type_info recaulk_ti_P##code                 \
      __asm__("__ZTIP" #code) = {RECAULK_VT(recaulk_pointer_vt), recaulk_ts_P##code, 0,           \
                                 &recaulk_ti_##code};                                             \
  __attribute__((weak)) const char recaulk_ts_PK##code[] __asm__("__ZTSPK" #code) = "PK" #code;    \
  __attribute__((weak)) const struct recaulk_pointer_type_info recaulk_ti_PK##code                \
      __asm__("__ZTIPK" #code) = {RECAULK_VT(recaulk_pointer_vt), recaulk_ts_PK##code,             \
                                  RECAULK_CONST_MASK, &recaulk_ti_##code};

RECAULK_FUNDAMENTAL(Dh)
RECAULK_FUNDAMENTAL(Du)
RECAULK_FUNDAMENTAL(g)
RECAULK_FUNDAMENTAL(n)
RECAULK_FUNDAMENTAL(o)
