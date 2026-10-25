#ifndef RECAULK_OS_SYSTEM_VERSION_H
#define RECAULK_OS_SYSTEM_VERSION_H

#ifdef __cplusplus
extern "C" {
#endif

/* spec: PROVENANCE.md, "os_system_version_get_current_version"; declared as Swift's Availability.mm does */
struct os_system_version_s {
	unsigned int major;
	unsigned int minor;
	unsigned int patch;
};

int os_system_version_get_current_version(struct os_system_version_s *version);

#ifdef __cplusplus
}
#endif

#endif
