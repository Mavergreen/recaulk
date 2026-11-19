/*
 * dispatch_get_global_queue, public, for libRecaulkSystem.dylib -- Recaulk's own. A program relinked onto the dylib
 * binds the name to it, so a QoS class gets a global queue (src/backfills/dispatch_global_qos.c). In the dylib this
 * replaces the weak hidden copy librecaulk.a keeps for the image that links it.
 */
#include <dispatch/dispatch.h>

dispatch_queue_t __recaulk_dispatch_get_global_queue(long identifier, unsigned long flags);

dispatch_queue_t recaulk_export_dispatch_get_global_queue(long, unsigned long) __asm("_dispatch_get_global_queue");
dispatch_queue_t recaulk_export_dispatch_get_global_queue(long identifier, unsigned long flags) {
    return __recaulk_dispatch_get_global_queue(identifier, flags);
}
