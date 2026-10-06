#include <dlfcn.h>

__attribute__((visibility("hidden")))
void *__recaulk_resolve(const char *name, void *impl, void **slot) {
  void *found = dlsym(RTLD_NEXT, name);
  if (found == 0) {
    (void)dlerror();
    found = impl;
  }
  __atomic_store_n(slot, found, __ATOMIC_RELEASE);
  return found;
}
