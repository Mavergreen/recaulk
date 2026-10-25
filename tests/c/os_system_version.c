#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <os/system_version.h>

_Static_assert(sizeof(struct os_system_version_s) == 12, "Swift's Availability.mm declares three unsigned ints");
_Static_assert(offsetof(struct os_system_version_s, major) == 0, "major first");
_Static_assert(offsetof(struct os_system_version_s, minor) == 4, "minor second");
_Static_assert(offsetof(struct os_system_version_s, patch) == 8, "patch third");

extern void *__recaulk_slot_os_system_version_get_current_version;

int main(void) {
  struct os_system_version_s v = {0, 0, 0};
  Dl_info info, self;
  int rc = os_system_version_get_current_version(&v);
  printf("rc: %d\n", rc);
  printf("version: %u.%u.%u\n", v.major, v.minor, v.patch);
  if (!dladdr(__recaulk_slot_os_system_version_get_current_version, &info)) {
    printf("target: (dladdr failed for %p)\n", __recaulk_slot_os_system_version_get_current_version);
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
