/* platform: MacPorts' sys/clonefile.h tests __MPLS_SDK_SUPPORT_CLONEFILE__ without including
   MacportsLegacySupport.h, which defines it, so on its own it reads 0 and #include_next's a header the
   10.9 SDK lacks. */
#include <MacportsLegacySupport.h>
#include <sys/_recaulk_macports_clonefile.h>
