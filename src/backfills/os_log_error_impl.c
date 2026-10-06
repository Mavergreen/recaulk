/*
 * os_log stubs (added macOS 10.12) --
 * custom polyfill (not from macports-legacy-support).
 *
 * Logging is disabled; the entry points exist only so modern binaries link
 * and run.
 */

void _os_log_error_impl(void *dso, void *log, int type,
                        const char *format, void *buf, unsigned int size) {
	(void)dso; (void)log; (void)type; (void)format; (void)buf; (void)size;
}
