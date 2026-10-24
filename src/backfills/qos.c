/*
 * pthread QoS (macOS 10.10+). A 10.9 kernel has no QoS classes, so these answer
 * as Apple's libpthread-105.1.4 does on a kernel without QoS support.
 */

#include <errno.h>
#include <pthread/qos.h>

int pthread_set_qos_class_self_np(qos_class_t qos_class, int relative_priority) {
	(void)qos_class; (void)relative_priority;
	return ENOTSUP;
}

int pthread_get_qos_class_np(pthread_t pthread, qos_class_t *qos_class, int *relative_priority) {
	(void)pthread; (void)qos_class; (void)relative_priority;
	return ENOTSUP;
}

int pthread_attr_set_qos_class_np(pthread_attr_t *attr, qos_class_t qos_class, int relative_priority) {
	(void)attr; (void)qos_class; (void)relative_priority;
	return ENOTSUP;
}

int pthread_attr_get_qos_class_np(pthread_attr_t *attr, qos_class_t *qos_class, int *relative_priority) {
	(void)attr; (void)qos_class; (void)relative_priority;
	return ENOTSUP;
}

pthread_override_t pthread_override_qos_class_start_np(pthread_t pthread, qos_class_t qos_class, int relative_priority) {
	(void)pthread; (void)qos_class; (void)relative_priority;
	return NULL;
}

int pthread_override_qos_class_end_np(pthread_override_t override) {
	(void)override;
	return EINVAL;
}
