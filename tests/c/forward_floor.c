#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

int mgfl_value(void);

static int lookups;

/* platform: stands in for dyld's answer for libsystem_kernel's version, which is xnu's (src/xnu_version.h),
   so one host can play 10.9 (xnu-2422) and a newer macOS: MGFL_XNU names xnu's major version */
int mgfl_nsversion(const char *library) {
  if (strcmp(library, "system_kernel") != 0) return -1;
  return atoi(getenv("MGFL_XNU")) << 16;
}

/* platform: counts lookups; on 10.9 a dlsym that finds nothing allocates, which is unsafe from
   inside an allocator that locks with a forwarded os_unfair_lock */
void *mgfl_counting_dlsym(void *handle, const char *name) {
  lookups++;
  return dlsym(handle, name);
}

int main(void) {
  int first = mgfl_value();
  int again = mgfl_value();
  printf("lookups %d\nvalue %d\nagain %d\n", lookups, first, again);
  return 0;
}
