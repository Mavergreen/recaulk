/*
 * qos_class_self / qos_class_main (macOS 10.10+, Apple's <sys/qos.h>) --
 * custom polyfill (not from macports-legacy-support).
 *
 * QOS_CLASS_DEFAULT for both. Every thread on 10.9, the main one included, is
 * scheduled the same way, so this is not a placeholder -- it is the only true
 * answer. Includes the declaring header so the compiler checks the signatures.
 */

#include <pthread/qos.h>

qos_class_t qos_class_self(void) {
	return QOS_CLASS_DEFAULT;
}

qos_class_t qos_class_main(void) {
	return QOS_CLASS_DEFAULT;
}
