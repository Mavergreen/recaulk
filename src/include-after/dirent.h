/* Appended after the unmodified MacPorts wrapper when staging headers. */
#ifndef RECAULK_FDOPENDIR_H
#define RECAULK_FDOPENDIR_H
#if __DARWIN_C_LEVEL >= 200809L
__BEGIN_DECLS
DIR *__recaulk_fdopendir(int) __DARWIN_ALIAS_I(__recaulk_fdopendir);
__END_DECLS
#define fdopendir __recaulk_fdopendir
#endif
#endif
