# Provenance

## Source

Recaulk's own C comes from `schmonz/Mavericks-Porting-Resources`, path `mavericks-legacy-support/`,
commit `e8b35b9641069977f4d5d2d0ea52a6909c4a1f02` (branch `kevent64-receipt-not-stash`, on top of
Wowfunhappy's `6ead179fc7c155c9ce2ce92642e6585ae0d8abb5`). Function bodies are verbatim. The one
content edit is that `src/include/os/log.h` and `src/backfills/dispatch_modern.c` include
`MacportsLegacySupport.h` where he included `LegacySupport.h`.

## Imported files

| Mavericks-Porting-Resources path | Recaulk path | License, author |
|---|---|---|
| `mavericks-legacy-support/src/dlopen_interpose.c` | `src/overrides/dlopen_interpose.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dnssd_process_result.c` | `src/overrides/dnssd_process_result.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/init_offsets.c` | `src/overrides/init_offsets.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/ioctl_winsize.c` | `src/overrides/ioctl_winsize.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/jit.c` | `src/overrides/jit.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/kevent64_shim.c` | `src/overrides/kevent64_shim.c` | ISC, Wowfunhappy; EV_RECEIPT fix by Amitai Schleier, e8b35b9 |
| `mavericks-legacy-support/src/objc_read_class_pair.c` | `src/overrides/objc_read_class_pair.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/posix_spawn_chdir.c` | `src/overrides/posix_spawn_chdir.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/security.c` | `src/overrides/security.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/write_underline.c` | `src/overrides/write_underline.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/aligned_alloc.c` | `src/backfills/aligned_alloc.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/ccrandom.c` | `src/backfills/ccrandom.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/chk_fail.c` | `src/backfills/chk_fail.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/chkstk_darwin.c` | `src/backfills/chkstk_darwin.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dispatch.c` | `src/backfills/dispatch.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dispatch_modern.c` | `src/backfills/dispatch_modern.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dnssd_getaddrinfo_ex.c` | `src/backfills/dnssd_getaddrinfo_ex.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dyld_shim.c` | `src/backfills/dyld_shim.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/fd_set_overflow.c` | `src/backfills/fd_set_overflow.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/half_float.c` | `src/backfills/half_float.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/iokit.c` | `src/backfills/iokit.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/launchservices.c` | `src/backfills/launchservices.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/mkostemp.c` | `src/backfills/mkostemp.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/msg_x.c` | `src/backfills/msg_x.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/notify.c` | `src/backfills/notify.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/objc_runtime.c` | `src/backfills/objc_runtime.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/os_log.c` | `src/backfills/os_log.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/os_unfair_lock_assert.c` | `src/backfills/os_unfair_lock_assert.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/os_unfair_lock_ext.c` | `src/backfills/os_unfair_lock_ext.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/os_version.c` | `src/backfills/os_version.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/osatomic.c` | `src/backfills/osatomic.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/preadv_pwritev_nocancel.c` | `src/backfills/preadv_pwritev_nocancel.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/pthread_self_is_exiting.c` | `src/backfills/pthread_self_is_exiting.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/qos.c` | `src/backfills/qos.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/renameatx_np.c` | `src/backfills/renameatx_np.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/signpost.c` | `src/backfills/signpost.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/syslog_extsn.c` | `src/backfills/syslog_extsn.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/thread_register_values.c` | `src/backfills/thread_register_values.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/timingsafe_bcmp.c` | `src/backfills/timingsafe_bcmp.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/ulock.c` | `src/backfills/ulock.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/weak_custom_rr.c` | `src/backfills/weak_custom_rr.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/mav_shim_debug.h` | `src/mav_shim_debug.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/Security/Authorization.h` | `src/include/Security/Authorization.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/dispatch/dispatch.h` | `src/include/dispatch/dispatch.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/notify.h` | `src/include/notify.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/os/log.h` | `src/include/os/log.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/pthread/qos.h` | `src/include/pthread/qos.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/sys/_types/_mbstate_t.h` | `src/include/sys/_types/_mbstate_t.h` | ISC, Wowfunhappy |

## Dropped: MacPorts-derived files

The 19 files below are MacPorts legacy-support's own code, and the same names exist in its
`src/` at 1.5.2. Recaulk builds MacPorts itself as the ingredient, so importing them would
define the same symbols twice.

`atcalls.c atcalls.h clonefile.c compiler.h dirfuncs_compat.c dirfuncs_compat.h fdopendir.c
fmemopen.c fsgetpath.c getentropy.c memstream.c os_unfair_lock.c pthread_chdir.c
pthread_get_stacksize_np.c statxx.c sysconf.c time.c util.h utimensat.c`

## Dropped: his headers

`include/LegacySupport.h` is dropped: it redefines MacPorts' `__MPLS_TARGET_OSVER`. His other 20
headers are MacPorts' own, de-gated, and are dropped too. Two of them carried additions of his:
`os_unfair_lock_assert_owner` in `os/lock.h` and `aligned_alloc` in `stdlib.h`. They sit at
MacPorts' paths, so those two declarations do not ship.

## Parity fixture

`tests/fixtures/libSystemWrapper-exports.txt` is the export list of Mavericks Forever's shipped
`libSystemWrapper.dylib`, sha256 `173e9b89c1941b6a1caa7c79c4dd015ae2e2117de9aed42f5d925ed70a8362d7`,
194 symbols:

    nm -gU libSystemWrapper.dylib | awk '{print $3}' | LC_ALL=C sort -u
