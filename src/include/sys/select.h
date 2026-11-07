/* spec: README.md "Fixes to functions 10.9 has" -- a program built from source calls Recaulk's pselect whatever
   its link order. A rename, not a declaration first: 10.9's own declaration names one of five symbols by asm
   label, and through this name the label it picks is Recaulk's ___recaulk_pselect_entry with the same suffix.
   Not inside Recaulk, whose own sources define the 10.9 names. */
#ifndef __RECAULK_SOURCE__
#define pselect __recaulk_pselect_entry
#endif
#include_next <sys/select.h>
