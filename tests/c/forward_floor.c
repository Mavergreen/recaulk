#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

int mgfl_value(void);

static int lookups;

/* platform: stands in for the kernel's kern.osrelease, so one host can play 10.9 (Darwin 13) and a
   newer macOS: MGFL_OSRELEASE names the release */
int mgfl_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
  const char *rel = getenv("MGFL_OSRELEASE");
  size_t n = strlen(rel) + 1;
  (void)name; (void)namelen; (void)newp; (void)newlen;
  if (oldp == 0 || *oldlenp < n) return -1;
  memcpy(oldp, rel, n);
  *oldlenp = n;
  return 0;
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
