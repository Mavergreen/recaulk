/*
 * qos_class_self / qos_class_main (macOS 10.10+, Apple's <sys/qos.h>). A 10.9
 * kernel assigns no QoS class, so both report QOS_CLASS_UNSPECIFIED, as Apple's
 * libpthread-105.1.4 does on a kernel without QoS support.
 */

#include <pthread/qos.h>

qos_class_t qos_class_self(void) {
	return QOS_CLASS_UNSPECIFIED;
}

qos_class_t qos_class_main(void) {
	return QOS_CLASS_UNSPECIFIED;
}
