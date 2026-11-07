/* platform: MacPorts' sys/fsgetpath.h declares fsgetpath with ssize_t, size_t, uint64_t and struct fsid
   but includes none of them; the 11.3 SDK's own header includes each. */
#include <sys/types.h>
#include <sys/mount.h>
#include <stdint.h>
#include <sys/_recaulk_macports_fsgetpath.h>
