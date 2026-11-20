/* spec: README.md "Declarations" -- MacPorts names MAP_ANONYMOUS as MAP_ANON unconditionally, but 10.9's
   <sys/mman.h> names MAP_ANON only when !_POSIX_C_SOURCE || _DARWIN_C_SOURCE. Elsewhere the name would expand
   to an undeclared one, and a strict-POSIX `#ifdef MAP_ANONYMOUS` would take the branch that cannot compile. */
#include <sys/cdefs.h>
#include <sys/_recaulk_macports_mman.h>
#ifndef MAP_ANON
#undef MAP_ANONYMOUS
#endif
