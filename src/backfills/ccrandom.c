/*
 * CCRandomGenerateBytes (introduced in macOS 10.10) --
 * custom polyfill (not from macports-legacy-support).
 */

#include <stddef.h>
#include <stdlib.h>

int CCRandomGenerateBytes(void *bytes, size_t count) {
	if (count == 0) {
		return 0; /* kCCSuccess */
	}
	if (bytes == NULL) {
		return -4300; /* kCCParamError */
	}
	arc4random_buf(bytes, count);
	return 0;
}
