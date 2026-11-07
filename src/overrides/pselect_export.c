/*
 * pselect's five 10.9 symbols, public, for libRecaulkSystem.dylib -- Recaulk's own. A program relinked
 * onto the dylib binds these names to it, so its waits never lose a signal (src/backfills/pselect.c).
 * In the dylib these replace the weak hidden copies that librecaulk.a keeps for the image that links it.
 */
#include <signal.h>
#include <sys/select.h>
#include <time.h>

#define RECAULK_PSELECT_EXTSN 1
#define RECAULK_PSELECT_NOCANCEL 2
#define RECAULK_PSELECT_LEGACY 4

int __recaulk_pselect(int variant, int nfds, fd_set *r, fd_set *w, fd_set *e,
                      const struct timespec *timeout, const sigset_t *mask);
void __recaulk_pselect_early(void);

/* spec: src/backfills/pselect.c -- register the main thread's kqueue as the dylib loads, before any
 * signal can be under way; an override may have a constructor, a back-fill may not. */
__attribute__((constructor)) static void register_early(void) { __recaulk_pselect_early(); }

#define EXPORT(name, symbol, variant)                                                                  \
    int name(int, fd_set *, fd_set *, fd_set *, const struct timespec *, const sigset_t *) __asm(symbol); \
    int name(int nfds, fd_set *r, fd_set *w, fd_set *e, const struct timespec *t, const sigset_t *m) {   \
        return __recaulk_pselect(variant, nfds, r, w, e, t, m);                                          \
    }
EXPORT(recaulk_export_pselect_legacy, "_pselect", RECAULK_PSELECT_LEGACY)
EXPORT(recaulk_export_pselect_1050, "_pselect$1050", 0)
EXPORT(recaulk_export_pselect_extsn, "_pselect$DARWIN_EXTSN", RECAULK_PSELECT_EXTSN)
EXPORT(recaulk_export_pselect_extsn_nocancel, "_pselect$DARWIN_EXTSN$NOCANCEL", RECAULK_PSELECT_EXTSN | RECAULK_PSELECT_NOCANCEL)
EXPORT(recaulk_export_pselect_nocancel, "_pselect$NOCANCEL", RECAULK_PSELECT_NOCANCEL)
