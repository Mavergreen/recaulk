/*
 * close, close$NOCANCEL and dup2, public, for libRecaulkSystem.dylib -- Recaulk's own. A program relinked onto
 * the dylib binds these names to it, so closing a socket another thread is entering a read on never hangs
 * (src/backfills/socket_close.c). In the dylib these replace the weak hidden copies librecaulk.a keeps for the
 * image that links it.
 */
int __recaulk_close(int fd);
int __recaulk_close_nocancel(int fd);
int __recaulk_dup2(int from, int to);

int recaulk_export_close(int) __asm("_close");
int recaulk_export_close(int fd) { return __recaulk_close(fd); }
int recaulk_export_close_nocancel(int) __asm("_close$NOCANCEL");
int recaulk_export_close_nocancel(int fd) { return __recaulk_close_nocancel(fd); }
int recaulk_export_dup2(int, int) __asm("_dup2");
int recaulk_export_dup2(int from, int to) { return __recaulk_dup2(from, to); }
