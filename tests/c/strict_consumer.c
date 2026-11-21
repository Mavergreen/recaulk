/* A product's use of Recaulk's dispatch calls, for tests/strict-guard-consumer.sh to measure with the strict guard. */
#include <dispatch/dispatch.h>

int main(int argc, char **argv) {
    (void)argv;
    dispatch_queue_attr_t a = dispatch_queue_attr_make_initially_inactive(argc > 1 ? DISPATCH_QUEUE_CONCURRENT : DISPATCH_QUEUE_SERIAL);
    a = dispatch_queue_attr_make_with_qos_class(a, QOS_CLASS_UTILITY, 0);
    dispatch_queue_t q = dispatch_queue_create("recaulk.strict", a);
    dispatch_activate(q);
    return dispatch_queue_get_qos_class(q, NULL) == QOS_CLASS_UTILITY ? 0 : 1;
}
