/* platform: MacPorts' sys/random.h declares getentropy with size_t but includes nothing that defines it. */
#include <sys/types.h>
#include <sys/_recaulk_macports_random.h>
