/*
 * dnssd_getaddrinfo_ex.c -- back-port the newer DNSServiceGetAddrInfoEx SPI.
 *
 * The Ex entry point is DNSServiceGetAddrInfo plus an opaque attribute.  Newer
 * Bun uses kDNSServiceAttrAllowFailover so scoped DNS queries may fall back to
 * the default resolver.  Mavericks predates both symbols, but its ordinary
 * DNSServiceGetAddrInfo already uses the system resolver path.  Export a token
 * for the opaque attribute (dnssd_attr_allow_failover.c) and delegate the
 * request while ignoring that token.
 */
#include <dns_sd.h>
#include <stdint.h>

DNSServiceErrorType DNSServiceGetAddrInfoEx(
    DNSServiceRef *sdRef,
    DNSServiceFlags flags,
    uint32_t interfaceIndex,
    DNSServiceProtocol protocol,
    const char *hostname,
    const void *attribute,
    DNSServiceGetAddrInfoReply callBack,
    void *context)
{
    (void)attribute;
    return DNSServiceGetAddrInfo(sdRef, flags, interfaceIndex, protocol,
                                 hostname, callBack, context);
}
