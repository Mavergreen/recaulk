/*
 * os_log stubs (added macOS 10.12) --
 * custom polyfill (not from macports-legacy-support).
 *
 * Logging is disabled; this is the shared disabled-log handle that
 * os_log_create returns.
 */

struct os_log_s { int dummy; };
static struct os_log_s _os_log_default_val = { 0 };
void *_os_log_default = &_os_log_default_val;
