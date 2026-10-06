#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main(int argc, char **argv) {
  const char *want = "/libRecaulkSystem.dylib";
  struct timespec ts;
  Dl_info info;
  uint32_t i;
  uintptr_t addr;
  if (argc != 2) return 2;
  addr = (uintptr_t)strtoull(argv[1], 0, 16);
  printf("rc: %d\n", clock_gettime(CLOCK_REALTIME, &ts));
  for (i = 0; i < _dyld_image_count(); i++) {
    const char *name = _dyld_get_image_name(i);
    size_t n = strlen(name), w = strlen(want);
    if (n >= w && strcmp(name + n - w, want) == 0) {
      void *slot = *(void **)(addr + (uintptr_t)_dyld_get_image_vmaddr_slide(i));
      printf("dylib: %s\n", name);
      if (slot != 0 && dladdr(slot, &info))
        printf("target: %s\n", info.dli_fname);
      else
        printf("target: (slot holds %p)\n", slot);
      return 0;
    }
  }
  printf("dylib: (not loaded)\n");
  return 1;
}
