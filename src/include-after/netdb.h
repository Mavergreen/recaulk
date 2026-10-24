/* Appended after the unmodified MacPorts wrapper when staging headers. */
#ifndef RECAULK_NETDB_H
#define RECAULK_NETDB_H
#include <string.h>

/* platform: Mavericks' mdns_addrinfo dereferences NULL when AI_NUMERICSERV
 * accompanies a NULL or exactly "0" service. Both already denote numeric port
 * zero, so suppressing the redundant flag preserves the requested lookup.
 * Named services retain AI_NUMERICSERV and must still be rejected. Keeping the
 * adaptation here also covers source consumers of the static library without
 * defining a symbol that the 10.9 SDK already exports. */
static inline int __recaulk_getaddrinfo(const char *node, const char *service,
                                      const struct addrinfo *hints,
                                      struct addrinfo **result) {
    struct addrinfo adjusted;
    if (hints && (hints->ai_flags & AI_NUMERICSERV) &&
        (!service || strcmp(service, "0") == 0)) {
        adjusted = *hints;
        adjusted.ai_flags &= ~AI_NUMERICSERV;
        hints = &adjusted;
    }
    return getaddrinfo(node, service, hints, result);
}
#define getaddrinfo __recaulk_getaddrinfo
#endif
