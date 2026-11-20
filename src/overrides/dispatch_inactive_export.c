/*
 * dispatch_queue_create and dispatch_resume, public, for libRecaulkSystem.dylib -- Recaulk's own. A program relinked onto the dylib binds
 * the names to it, so an initially inactive attribute makes an inactive queue, and a resume counts as its activation (src/backfills/dispatch_inactive.c). In
 * the dylib these replace the weak hidden copies librecaulk.a keeps for the image that links it.
 */
#include <dispatch/dispatch.h>

dispatch_queue_t __recaulk_dispatch_queue_create(const char *label, dispatch_queue_attr_t attr);

dispatch_queue_t recaulk_export_dispatch_queue_create(const char *, dispatch_queue_attr_t) __asm("_dispatch_queue_create");
dispatch_queue_t recaulk_export_dispatch_queue_create(const char *label, dispatch_queue_attr_t attr) {
    return __recaulk_dispatch_queue_create(label, attr);
}

void __recaulk_dispatch_resume(dispatch_object_t object);

void recaulk_export_dispatch_resume(dispatch_object_t) __asm("_dispatch_resume");
void recaulk_export_dispatch_resume(dispatch_object_t object) { __recaulk_dispatch_resume(object); }
