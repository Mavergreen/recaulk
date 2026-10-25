#include <dlfcn.h>
#include <stdio.h>
#include <os/system_version.h>
#include <pthread/qos.h>

extern void *__recaulk_slot_os_system_version_get_current_version;
extern void *__recaulk_slot_qos_class_self;

static const char *image(const void *p) {
  Dl_info info;
  if (p == 0) return "(none)";
  return dladdr(p, &info) ? info.dli_fname : "(dladdr failed)";
}

void forward_dylib_probe(void) {
  struct os_system_version_s v = {0, 0, 0};
  int rc;
  qos_class_t q;
  printf("osv-slot-before: %s\n", image(__recaulk_slot_os_system_version_get_current_version));
  printf("qos-slot-before: %s\n", image(__recaulk_slot_qos_class_self));
  rc = os_system_version_get_current_version(&v);
  q = qos_class_self();
  printf("osv-rc: %d\n", rc);
  printf("osv-version: %u.%u.%u\n", v.major, v.minor, v.patch);
  printf("osv-target: %s\n", image(__recaulk_slot_os_system_version_get_current_version));
  printf("qos: %u\n", (unsigned)q);
  printf("qos-target: %s\n", image(__recaulk_slot_qos_class_self));
  printf("self: %s\n", image((const void *)forward_dylib_probe));
  printf("next-osv: %s\n", image(dlsym(RTLD_NEXT, "os_system_version_get_current_version")));
  printf("next-qos: %s\n", image(dlsym(RTLD_NEXT, "qos_class_self")));
  printf("next-getpid: %s\n", image(dlsym(RTLD_NEXT, "getpid")));
  printf("default-qos: %s\n", image(dlsym(RTLD_DEFAULT, "qos_class_self")));
}
