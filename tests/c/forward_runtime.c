#include <dlfcn.h>
#include <stdio.h>
#include <time.h>

extern void *__recaulk_slot_clock_gettime;

int main(void) {
  struct timespec ts;
  Dl_info info, self;
  int rc = clock_gettime(CLOCK_REALTIME, &ts);
  printf("rc: %d\n", rc);
  if (!dladdr(__recaulk_slot_clock_gettime, &info)) {
    printf("target: (dladdr failed for %p)\n", __recaulk_slot_clock_gettime);
    return 1;
  }
  if (!dladdr((void *)main, &self)) {
    printf("self: (dladdr failed)\n");
    return 1;
  }
  printf("target: %s\n", info.dli_fname);
  printf("self: %s\n", self.dli_fname);
  return 0;
}
