/*
 * os_log stubs (added macOS 10.12) --
 * custom polyfill (not from macports-legacy-support).
 *
 * Logging is disabled; the entry points exist only so modern binaries link
 * and run.
 */

extern void *_os_log_default;  /* os_log_default.c */

/* os_log_create (added 10.12): returns a logger handle. Logging is disabled, so
 * hand back the shared disabled handle rather than allocating. Must never be
 * NULL -- callers store it and pass it to os_log_type_enabled (returns 0) and
 * _os_log_impl (no-op), and may compare it against OS_LOG_DEFAULT. */
void *os_log_create(const char *subsystem, const char *category) {
	(void)subsystem; (void)category;
	return _os_log_default;
}
