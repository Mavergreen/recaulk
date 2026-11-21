/*
 * dispatch_queue_attr_make_with_qos_class (10.10), Recaulk's on every system (build/forward-exclude.txt, self), in a
 * member of its own so a consumer that defines it collides with nothing else. README.md "Dispatch on 10.9". The work,
 * which shares Recaulk's attribute records, is in src/backfills/dispatch_inactive.c.
 */
#include <dispatch/dispatch.h>

__attribute__((visibility("hidden"))) dispatch_queue_attr_t __recaulk_dispatch_attr_with_qos(dispatch_queue_attr_t attr,
    dispatch_qos_class_t qos_class, int relative_priority);

dispatch_queue_attr_t dispatch_queue_attr_make_with_qos_class(dispatch_queue_attr_t attr, dispatch_qos_class_t qos_class,
                                                              int relative_priority) {
    return __recaulk_dispatch_attr_with_qos(attr, qos_class, relative_priority);
}
