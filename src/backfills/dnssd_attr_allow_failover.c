/*
 * dnssd_attr_allow_failover.c -- the opaque attribute token that
 * DNSServiceGetAddrInfoEx (dnssd_getaddrinfo_ex.c) accepts and ignores.
 */

/* Callers only obtain and pass this symbol's address; its representation is
 * deliberately opaque.  A byte gives it stable storage without pretending to
 * know the private structure used by newer mDNSResponder versions. */
const unsigned char kDNSServiceAttrAllowFailover = 0;
