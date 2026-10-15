#include <dlfcn.h>
#include <sys/sysctl.h>

/* platform: the forwarded set is what the 10.9 SDK does not export (build/forward-set.sh), so on
   10.9 (Darwin 13) or older a lookup can only fail, and a dlsym that fails allocates its dlerror
   buffer. Called from inside an allocator built for 10.12, as when upstream rustc's jemalloc locks
   with os_unfair_lock, that allocation re-enters the allocator mid-lock and crashes. There the
   back-fill is the answer without a lookup; sysctl by MIB asks the kernel and allocates nothing. */
static int on_floor(void) {
  static int floor = -1;
  int f = __atomic_load_n(&floor, __ATOMIC_RELAXED);
  if (f < 0) {
    int mib[2] = {CTL_KERN, KERN_OSRELEASE}, major = 0;
    char rel[32];
    size_t n = sizeof rel;
    const char *p;
    if (sysctl(mib, 2, rel, &n, 0, 0) == 0)
      for (p = rel; p < rel + n && *p >= '0' && *p <= '9'; p++)
        major = major * 10 + (*p - '0');
    f = major > 0 && major <= 13;
    __atomic_store_n(&floor, f, __ATOMIC_RELAXED);
  }
  return f;
}

__attribute__((visibility("hidden")))
void *__recaulk_resolve(const char *name, void *impl, void **slot) {
  void *found = impl;
  if (!on_floor()) {
    found = dlsym(RTLD_NEXT, name);
    if (found == 0) {
      (void)dlerror();
      found = impl;
    }
  }
  __atomic_store_n(slot, found, __ATOMIC_RELEASE);
  return found;
}
