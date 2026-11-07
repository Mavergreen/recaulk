#include <mach/mach.h>
#ifndef RECAULK_MACH_THREAD_STATE_H
#define RECAULK_MACH_THREAD_STATE_H
#ifndef __ASSEMBLER__
/* spec: the 11.3 SDK's mach/thread_state.h, which 10.9's lacks, declares thread_get_register_pointer_values under exactly this condition. */
#if !defined(KERNEL)
__BEGIN_DECLS
kern_return_t thread_get_register_pointer_values(thread_t thread, uintptr_t *sp, size_t *length, uintptr_t *values);
__END_DECLS
#endif
#endif
#endif
