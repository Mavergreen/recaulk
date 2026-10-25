#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <os/system_version.h>
#include <pthread/qos.h>

#ifdef LINKED
void forward_dylib_probe(void);
#endif

int main(int argc, char **argv) {
  void *sys = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOLOAD);
  int (*osv)(struct os_system_version_s *) = 0;
  qos_class_t (*qos)(void) = 0;
  void (*probe)(void) = 0;
  setvbuf(stdout, 0, _IONBF, 0);
  if (sys == 0) { printf("system: (libSystem not loaded)\n"); return 1; }
  osv = (int (*)(struct os_system_version_s *))dlsym(sys, "os_system_version_get_current_version");
  qos = (qos_class_t (*)(void))dlsym(sys, "qos_class_self");
#ifdef LINKED
  probe = forward_dylib_probe;
  (void)argc; (void)argv;
#else
  {
    void *h;
    if (argc != 2) return 2;
    h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (h == 0) { printf("dlopen: %s\n", dlerror()); return 1; }
    probe = (void (*)(void))dlsym(h, "forward_dylib_probe");
    if (probe == 0) { printf("dlsym: no forward_dylib_probe\n"); return 1; }
  }
#endif
  if (osv) {
    struct os_system_version_s v = {0, 0, 0};
    int rc = osv(&v);
    printf("system-osv: %d %u.%u.%u\n", rc, v.major, v.minor, v.patch);
  } else {
    printf("system-osv: (none)\n");
  }
  if (qos)
    printf("system-qos: %u\n", (unsigned)qos());
  else
    printf("system-qos: (none)\n");
  probe();
  return 0;
}
