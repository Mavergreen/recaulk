#include <Security/SecureTransport.h>
#include <stdio.h>

/* Recaulk exports it without declaring it (build/declarations.txt says why), so the test declares it. */
OSStatus SSLSetSessionTicketsEnabled(SSLContextRef context, Boolean enabled);

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

int main(void) {
	SSLContextRef ctx = SSLCreateContext(NULL, kSSLClientSide, kSSLStreamType);
	SSLSessionState before, after;
	OSStatus s;
	CHECK(ctx != NULL, "SSLCreateContext failed");
	if (!ctx) return 1;
	CHECK(SSLGetSessionState(ctx, &before) == 0, "SSLGetSessionState failed");
	s = SSLSetSessionTicketsEnabled(ctx, false);
	CHECK(s == 0, "disabling tickets returned %d, want 0: 10.9 never uses them", (int)s);
	s = SSLSetSessionTicketsEnabled(ctx, true);
	/* errSecUnimplemented: 10.9's SecureTransport cannot honour the request, and must not claim to. */
	CHECK(s == -4, "enabling tickets returned %d, want -4 (errSecUnimplemented)", (int)s);
	CHECK(SSLGetSessionState(ctx, &after) == 0 && after == before, "the refused request changed the context's state");
	s = SSLSetSessionTicketsEnabled(NULL, false);
	CHECK(s == -50, "a NULL context, disabling, returned %d, want -50 (errSecParam)", (int)s);
	s = SSLSetSessionTicketsEnabled(NULL, true);
	CHECK(s == -50, "a NULL context, enabling, returned %d, want -50 (errSecParam)", (int)s);
	CFRelease(ctx);
	if (failures) return 1;
	printf("ssl_session_tickets: ok\n");
	return 0;
}
