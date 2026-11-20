/*
 * dispatch_queue_create, public, for libRecaulkSystem.dylib -- Recaulk's own. A program relinked onto the dylib binds
 * the name to it, so an initially inactive attribute makes an inactive queue (src/backfills/dispatch_inactive.c). In
 * the dylib this replaces the weak hidden copy librecaulk.a keeps for the image that links it.
 */
#include <dispatch/dispatch.h>

dispatch_queue_t __recaulk_dispatch_queue_create(const char *label, dispatch_queue_attr_t attr);

dispatch_queue_t recaulk_export_dispatch_queue_create(const char *, dispatch_queue_attr_t) __asm("_dispatch_queue_create");
dispatch_queue_t recaulk_export_dispatch_queue_create(const char *label, dispatch_queue_attr_t attr) {
    return __recaulk_dispatch_queue_create(label, attr);
}
