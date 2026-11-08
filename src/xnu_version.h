/*
 * The running kernel's xnu version, asked of dyld without a system call.
 *
 * platform: libsystem_kernel.dylib's current_version is its xnu version (10.9.5: 2422.115.15;
 * the 11.3 SDK's libsystem_kernel.tbd: 7195.101.1), so its major is xnu's: 2422 is Darwin 13
 * (10.9), 2782 Darwin 14 (10.10), 3248 Darwin 15 (10.11). dyld reads it from the image already
 * loaded, so it allocates nothing and asks the kernel nothing. A sysctl would: under a sandbox
 * profile of (deny default), as sshd-auth runs, kern.osrelease is a denied sysctl-read, and the
 * kernel's report of it starts sandboxd (packer, 2026-11-07; tests/sandbox-quiet.sh).
 * Returns 0 if dyld does not know the image.
 */
#ifndef RECAULK_XNU_VERSION_H
#define RECAULK_XNU_VERSION_H
#include <mach-o/dyld.h>
#include <stdint.h>

static inline int recaulk_xnu_major(void) {
    int32_t v = NSVersionOfRunTimeLibrary("system_kernel");
    return v > 0 ? (int)((uint32_t)v >> 16) : 0;
}
#endif
