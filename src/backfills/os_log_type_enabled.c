/*
 * os_log stubs (added macOS 10.12) --
 * custom polyfill (not from macports-legacy-support).
 *
 * Logging is disabled; the entry points exist only so modern binaries link
 * and run.
 */

int os_log_type_enabled(void *log, int type) {
	(void)log; (void)type;
	return 0; /* logging disabled */
}
