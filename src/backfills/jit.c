/*
 * JIT support shims -- custom polyfill (not from macports-legacy-support).
 */

/*
 * pthread_jit_write_protect_np (added macOS 11.0)
 * On x86_64, this is a no-op.
 */
void pthread_jit_write_protect_np(int enabled) {
	(void)enabled;
}
