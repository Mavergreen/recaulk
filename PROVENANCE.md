# Provenance

## Source

Recaulk's own C comes from `schmonz/Mavericks-Porting-Resources`, path `mavericks-legacy-support/`,
commit `e8b35b9641069977f4d5d2d0ea52a6909c4a1f02` (branch `kevent64-receipt-not-stash`, on top of
Wowfunhappy's `6ead179fc7c155c9ce2ce92642e6585ae0d8abb5`). Function bodies are verbatim but for
the behaviour fixes recorded under Behaviour fixes. Beyond those fixes and the moves and splits recorded
below, his files differ in one way: `src/include/os/log.h` and `src/backfills/dispatch_modern.c` include
`MacportsLegacySupport.h` where he included `LegacySupport.h`.

## Imported files

| Mavericks-Porting-Resources path | Recaulk path | License, author |
|---|---|---|
| `mavericks-legacy-support/src/dlopen_interpose.c` | `src/overrides/dlopen_interpose.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dnssd_process_result.c` | `src/overrides/dnssd_process_result.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/init_offsets.c` | `src/overrides/init_offsets.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/ioctl_winsize.c` | `src/overrides/ioctl_winsize.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/jit.c` | `src/backfills/jit.c`, `src/overrides/mmap_jit.c` (split) | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/kevent64_shim.c` | `src/overrides/kevent64_shim.c` | ISC, Wowfunhappy; EV_RECEIPT fix by Amitai Schleier, e8b35b9 |
| `mavericks-legacy-support/src/objc_read_class_pair.c` | `src/backfills/objc_read_class_pair.c`, `src/backfills/objc_realize_class_from_swift.c` (moved, split) | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/posix_spawn_chdir.c` | `src/overrides/posix_spawn_chdir.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/security.c` | `src/backfills/security.c`, `src/backfills/security_k*.c` (one per constant), `src/overrides/sectrust_evaluate.c` (split) | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/write_underline.c` | `src/overrides/write_underline.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/aligned_alloc.c` | `src/backfills/aligned_alloc.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/ccrandom.c` | `src/backfills/ccrandom.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/chk_fail.c` | `src/backfills/chk_fail.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/chkstk_darwin.c` | `src/backfills/chkstk_darwin.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dispatch.c` | `src/backfills/dispatch.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dispatch_modern.c` | `src/backfills/dispatch_modern.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dnssd_getaddrinfo_ex.c` | `src/backfills/dnssd_getaddrinfo_ex.c`, `src/backfills/dnssd_attr_allow_failover.c` (split) | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/dyld_shim.c` | `src/backfills/dyld_shim.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/fd_set_overflow.c` | `src/backfills/fd_set_overflow.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/half_float.c` | `src/backfills/half_float.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/iokit.c` | `src/backfills/iokit.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/launchservices.c` | `src/backfills/launchservices.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/mkostemp.c` | `src/backfills/mkostemp.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/msg_x.c` | `src/backfills/msg_x.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/notify.c` | `src/backfills/notify.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/objc_runtime.c` | `src/backfills/objc_runtime.c`, `src/overrides/objc_alloc.c` (split) | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/os_log.c` | `src/backfills/os_log.c`, `src/backfills/os_log_default.c`, `src/backfills/os_log_type_enabled.c`, `src/backfills/os_log_error_impl.c`, `src/backfills/os_log_impl.c` (split) | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/os_unfair_lock_assert.c` | `src/backfills/os_unfair_lock_assert.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/os_unfair_lock_ext.c` | `src/backfills/os_unfair_lock_ext.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/os_version.c` | `src/backfills/os_version.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/osatomic.c` | `src/backfills/osatomic.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/preadv_pwritev_nocancel.c` | `src/backfills/preadv_pwritev_nocancel.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/pthread_self_is_exiting.c` | `src/backfills/pthread_self_is_exiting.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/qos.c` | `src/backfills/qos.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/renameatx_np.c` | `src/backfills/renameatx_np.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/signpost.c` | `src/backfills/signpost.c`, `src/backfills/signpost_enabled.c` (split) | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/syslog_extsn.c` | `src/backfills/syslog_extsn.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/thread_register_values.c` | `src/backfills/thread_register_values.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/timingsafe_bcmp.c` | `src/backfills/timingsafe_bcmp.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/ulock.c` | `src/backfills/ulock.c` | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/weak_custom_rr.c` | `src/overrides/weak_custom_rr.c` (moved) | ISC, Wowfunhappy |
| `mavericks-legacy-support/src/mav_shim_debug.h` | `src/mav_shim_debug.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/Security/Authorization.h` | `src/include/Security/Authorization.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/dispatch/dispatch.h` | `src/include/dispatch/dispatch.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/notify.h` | `src/include/notify.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/os/log.h` | `src/include/os/log.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/pthread/qos.h` | `src/include/pthread/qos.h` | ISC, Wowfunhappy |
| `mavericks-legacy-support/include/sys/_types/_mbstate_t.h` | `src/include/sys/_types/_mbstate_t.h` | ISC, Wowfunhappy |

## Moves and splits

Bodies are verbatim; each piece keeps the file's header comment and the includes it uses.

Moved because the rule 1 test named them (a back-fill may only add symbols 10.9 lacks; an override
must replace something 10.9 has):

- `weak_custom_rr.c`: back-fills to overrides. It defines `objc_copyWeak`, `objc_destroyWeak`,
  `objc_initWeak`, `objc_loadWeak`, `objc_loadWeakRetained`, `objc_moveWeak` and `objc_storeWeak`,
  which 10.9's libobjc already exports.
- `objc_read_class_pair.c`: overrides to back-fills. It replaces nothing 10.9 has.
- `objc_alloc`: out of `objc_runtime.c` into `objc_alloc.c` in overrides. 10.9's libobjc already
  exports `objc_alloc`; nothing else in `objc_runtime.c` calls it.

Split so that products linking `librecaulk.a` get the back-fill (the part 10.9 lacks), while the part
that replaces a 10.9 symbol stays an override:

- `security.c`: `SecPolicyCreateRevocation` and `SecTrustEvaluate` go to
  `overrides/sectrust_evaluate.c`. Everything else, including `SecTrustEvaluateWithError` and its
  helper `getStringForResultType`, stays in `backfills/security.c`.
- `jit.c`: `mmap` goes to `overrides/mmap_jit.c`; `pthread_jit_write_protect_np` stays as
  `backfills/jit.c`.

Split so that a call between two back-fills crosses objects and so reaches the forwarding layer's
trampoline (see Forwarding layer):

- `objc_read_class_pair.c`: `_objc_realizeClassFromSwift` goes to
  `backfills/objc_realize_class_from_swift.c`. It calls `objc_readClassPair`, which arrived in 10.10,
  and is itself 10.14.4. In one object that call would always reach our `objc_readClassPair`, which is
  written for 10.9's class layout, even on 10.10-10.14.3, where the system has its own. The static
  helpers and layout structs are used only by `objc_readClassPair` and stay with it. The 10.9 SDK does
  not declare `objc_readClassPair`, so the new file declares it. Its header's first sentence names the
  new file's function, and the function's comment no longer says "above".

Split so that every back-filled name stands alone in its archive member, and a consumer defining one
of them links without colliding with its neighbours:

- `security.c`: each of its 20 `kSec*` constants goes to its own `backfills/security_<constant>.c`.
  The functions stay; their names are owned by trampolines. The header comment's list of what the file
  covers no longer names constants.
- `os_log.c`: `_os_log_default` and its backing struct go to `backfills/os_log_default.c`. `os_log.c`
  declares `_os_log_default` `extern`.
- `dnssd_getaddrinfo_ex.c`: `kDNSServiceAttrAllowFailover` goes to
  `backfills/dnssd_attr_allow_failover.c`. The header comment's "Export a token" sentence points at
  the new file.

Split so that each function that takes a data symbol of ours, and so is never forwarded (see Forwarding
layer), stands alone under its own name in its archive member:

- `os_log.c`: `os_log_type_enabled`, `_os_log_error_impl` and `_os_log_impl` each go to their own
  `backfills/os_log_type_enabled.c`, `backfills/os_log_error_impl.c` and `backfills/os_log_impl.c`.
  `os_log_create`, which is forwarded, stays. Each piece keeps the header comment.
- `signpost.c`: `os_signpost_enabled` goes to `backfills/signpost_enabled.c`, whose header's first line
  names the new file. `_os_signpost_emit_with_name_impl` stays.

`posix_spawn_chdir.c` stays whole in overrides: its `addchdir_np` functions fill the table that its
`posix_spawn` wrapper reads.

## Behaviour fixes

`src/backfills/ccrandom.c`: behaviour fix (spec: back-fills match the real API): zero-length request
returns success, as Apple's does. A `NULL` buffer with a non-zero count still returns `kCCParamError`.

`src/backfills/security_k*.c`: behaviour fix (spec: back-fills match the real API). Eleven constants
carried strings that differ from Apple's. Data is never forwarded, so a program gets our constant on
every macOS; on 10.12 and later it hands it to the system's forwarded `SecKey` functions, or to its
`SecItem` functions, which then did not recognise it. Each now holds Apple's string, read from
`apple-oss-distributions/Security` at commit `db15acbe6a7f257a859ad9a3bb86097bfe0679d9`
(`https://github.com/apple-oss-distributions/Security/blob/db15acbe6a7f257a859ad9a3bb86097bfe0679d9/<path>`):

| Constant | Was | Apple's, now ours | Apple source |
|---|---|---|---|
| `kSecKeyAlgorithmECDHKeyExchangeStandard` | `algid:ecdh:standard` | `algid:keyexchange:ECDH` | `OSX/sec/Security/SecKeyAdaptors.m` line 160 |
| `kSecKeyAlgorithmECDSASignatureDigestX962` | `algid:ecdsa:digest-x962` | `algid:sign:ECDSA:digest-X962` | `OSX/sec/Security/SecKeyAdaptors.m` line 110 |
| `kSecKeyAlgorithmRSAEncryptionOAEPSHA1` | `algid:encrypt:RSA:OAEP-SHA1` | `algid:encrypt:RSA:OAEP:SHA1` | `OSX/sec/Security/SecKeyAdaptors.m` line 126 |
| `kSecKeyAlgorithmRSAEncryptionOAEPSHA256` | `algid:encrypt:RSA:OAEP-SHA256` | `algid:encrypt:RSA:OAEP:SHA256` | `OSX/sec/Security/SecKeyAdaptors.m` line 128 |
| `kSecKeyAlgorithmRSAEncryptionOAEPSHA384` | `algid:encrypt:RSA:OAEP-SHA384` | `algid:encrypt:RSA:OAEP:SHA384` | `OSX/sec/Security/SecKeyAdaptors.m` line 129 |
| `kSecKeyAlgorithmRSAEncryptionOAEPSHA512` | `algid:encrypt:RSA:OAEP-SHA512` | `algid:encrypt:RSA:OAEP:SHA512` | `OSX/sec/Security/SecKeyAdaptors.m` line 130 |
| `kSecKeyAlgorithmRSASignatureDigestPSSSHA1` | `algid:sign:RSA:digest-PSS:SHA1` | `algid:sign:RSA:digest-PSS:SHA1:SHA1:20` | `OSX/sec/Security/SecKeyAdaptors.m` line 77 |
| `kSecKeyAlgorithmRSASignatureDigestPSSSHA256` | `algid:sign:RSA:digest-PSS:SHA256` | `algid:sign:RSA:digest-PSS:SHA256:SHA256:32` | `OSX/sec/Security/SecKeyAdaptors.m` line 79 |
| `kSecKeyAlgorithmRSASignatureDigestPSSSHA384` | `algid:sign:RSA:digest-PSS:SHA384` | `algid:sign:RSA:digest-PSS:SHA384:SHA384:48` | `OSX/sec/Security/SecKeyAdaptors.m` line 80 |
| `kSecKeyAlgorithmRSASignatureDigestPSSSHA512` | `algid:sign:RSA:digest-PSS:SHA512` | `algid:sign:RSA:digest-PSS:SHA512:SHA512:64` | `OSX/sec/Security/SecKeyAdaptors.m` line 81 |
| `kSecUseDataProtectionKeychain` | `u-DataProtectionKeychain` | `nleg` | `OSX/sec/Security/SecItemConstants.c` line 174 |

The other nine already held Apple's strings:

- `kSecAttrKeyTypeECSECPrimeRandom` (`OSX/sec/Security/SecItemConstants.c` line 246)
- `kSecGuestAttributeAudit` (`OSX/libsecurity_codesigning/lib/SecCode.cpp` line 157)
- `kSecKeyAlgorithmRSAEncryptionPKCS1` (`OSX/sec/Security/SecKeyAdaptors.m` line 125)
- `kSecKeyAlgorithmRSAEncryptionRaw` (`OSX/sec/Security/SecKeyAdaptors.m` line 123)
- `kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA1` (`OSX/sec/Security/SecKeyAdaptors.m` line 72)
- `kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256` (`OSX/sec/Security/SecKeyAdaptors.m` line 74)
- `kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA384` (`OSX/sec/Security/SecKeyAdaptors.m` line 75)
- `kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA512` (`OSX/sec/Security/SecKeyAdaptors.m` line 76)
- `kSecKeyAlgorithmRSASignatureRaw` (`OSX/sec/Security/SecKeyAdaptors.m` line 67)

`tests/ksec-values.sh` pins all 20 strings against `tests/fixtures/ksec-values.txt`, and fails when
`librecaulk.a` defines a `kSec` constant the fixture does not pin.

`tests/c/test_polyfills.c` is verbatim except one test fix: it called `getentropy` with 256 and 257 on
the 64-byte `b1`, an overrun. It now declares `unsigned char big[257]` and uses it for those two calls.
That overrun is why it only survived an optimised build; the test builds without `-Os` now.

## Known MacPorts deviations and 10.9-fallback checks

`test_polyfills` links `librecaulk.a`, so on 10.12 and later its calls to a forwarded function reach the
system's implementation, not MacPorts'. Two fixtures say which of its checks depend on whose
implementation runs. Each line is `<MAJOR.MINOR`, a tab, and the check's condition as
`test_polyfills` prints it; the entry applies on a macOS below that version, where the system lacks the
function and ours runs.

`tests/fixtures/known-macports-deviations.txt` lists conditions that MacPorts' unmodified code fails.
`getentropy(big, 257) == -1 && errno == EIO` (`<10.12`): MacPorts' `getentropy` has no 256-byte limit
and returns 0. The system's refuses more than 256 bytes with -1. Impact: callers must chunk to 256
bytes; on 10.12 and later the call forwards to the system's, which has the limit. It goes upstream to
MacPorts. Where an entry applies, `shim-tests.sh` tolerates its failure and fails once it passes
("MacPorts fixed it"); where it does not, the system's implementation runs and the check must pass,
unless the next fixture lists it too.

`tests/fixtures/fallback-only-checks.txt` lists conditions that assert a 10.9-era expectation the
system's implementation does not meet. Where an entry applies it is an ordinary check; where it does
not, its result is printed but not judged.
- `clonefile(...) == -1 && errno == ENOTSUP` (`<10.12`): MacPorts' `clonefile` has no APFS to clone on,
  while the system's clones the file.
- `getentropy(big, 257) == -1 && errno == EIO` (`<10.12`): Apple's getentropy(2) manual page gives `EIO`
  for too many bytes, but xnu's `getentropy` system call returns `EINVAL` above 256 bytes
  (`bsd/dev/random/randomdev.c` in xnu-3789.1.32, macOS 10.12, and in every later release checked through `main`). macOS 26.6.2
  returned -1 with `EINVAL`. The check asserts the manual page's errno, so the system fails it.

Every other check is expected to pass in every era: header constants, calls 10.9 already makes, and
forwarded functions whose documented result is the same from MacPorts' implementation as from the
system's. Every entry in either fixture must appear in the output, as `ok` or `FAIL`.
`tests/polyfills-verdict.sh` runs the judgment against `tests/fixtures/test-polyfills-10.9.5.out`, the
output of a 10.9.5 run, with `sw_vers` stubbed to report 10.9.5, 10.11.6, 10.12, 14.0, 26.0 and
26.6.2, the last with the getentropy and clonefile failures macOS 26.6.2 printed.

## MacPorts' own tests under Rosetta 2

`tests/macports-own.sh` runs MacPorts' unmodified `make test_static` with `-k`. On Apple silicon the x86_64
test programs run under Rosetta 2, which reports mach time at 1 GHz while the kernel's
`SO_TIMESTAMP_MONOTONIC` packet stamp stays in the hardware's mach units, so the stamp reads about 41.7
times too small. MacPorts' `test/test_packet.c` describes this Rosetta 2 bug and ignores it, but only
when built for macOS 11 or later (`TARGET_OSVER >= 110000`); our 10.9 build compiles that check out.
`tests/fixtures/macports-own-rosetta.txt` names the four `test_packet` programs that check the stamp.
Under Rosetta 2, and only there, each may fail, if its only complaint is an underreported
`SO_TIMESTAMP_MONOTONIC` value; any other failure fails, and a listed program that passes under Rosetta 2
fails too ("remove it"). `tests/macports-own-verdict.sh` replays a native and a Rosetta 2 log.

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

## Forwarding layer

The forwarding layer is generated at build time and changes none of his sources. `build/build-lib.sh`
renames, in each built object, the forwarded functions that object defines (`___recaulk_impl_<name>`,
with drydock-macho-rewrite), and generates one assembly trampoline per name that owns the original
name. A reference from one object to a function another object defines keeps the original name, so the
linker binds it to the trampoline and every caller in a process reaches the same implementation: the
system's where it has one, ours where it does not. Members extracted with `ar -x` keep their archive padding after the string table; drydock 0.2.1 and
later accept that padding in a standalone object, so the members are renamed as extracted.

The trampoline preserves every integer and xmm register on its way to the implementation it jumps to
(the upper halves of the ymm registers are not saved; no forwarded function takes a 256-bit vector):
the cached path reads its slot from memory, and the first call saves and restores every argument register, `rax` (which
carries `al` for variadic calls), `r10`, `r11` and `xmm0`-`xmm15` around the resolver.

`build/forward-exclude.txt` lists the functions never forwarded, which `build/forward-set.sh` and
`tests/forward-derivation.sh` both read. Each line ends in why: `private` (MacPorts-private, which
`tests/one-backfill-per-member.sh` also skips, since no consumer defines them), `abi`, or `data`. A
function on the list stays defined under its own name.

| Entry | Why it is never forwarded |
|---|---|
| `name ____chkstk_darwin abi` | a stack probe whose callers keep every register but `rax` live; ours behaves the same on every macOS, so no trampoline stands in front of it |
| `prefix ___mpls_ private` | MacPorts' private helpers: no system exports them, and a trampoline would let `RTLD_NEXT` bind another image's private copy |
| `prefix _macports_legacy_ private` | MacPorts' private entry points (`macports_legacy_sysconf`), for the same reason |
| `name __error private` | MacPorts' private `_error` helper in `getentropy.c`, for the same reason |
| `name _DNSServiceGetAddrInfoEx data` | consumes a data symbol of ours: callers pass `&kDNSServiceAttrAllowFailover`, our one-byte placeholder, which the system's would read as its own attribute |
| `name __os_log_impl data` | consumes a data symbol of ours: Apple's headers make `OS_LOG_DEFAULT` the address of `_os_log_default`, which binds to ours, not to the system's log object |
| `name __os_log_error_impl data` | consumes a data symbol of ours, as `__os_log_impl` |
| `name _os_log_type_enabled data` | consumes a data symbol of ours, as `__os_log_impl` |
| `name __os_signpost_emit_with_name_impl data` | consumes a data symbol of ours, as `__os_log_impl` |
| `name _os_signpost_enabled data` | consumes a data symbol of ours, as `__os_log_impl` |

Data symbols are never forwarded, so a program always gets ours. A function that takes one stays ours
too, so the two always match: on 10.12 and later the `os_log` and `os_signpost` entry points stay our
no-ops, where the system would log. `os_log_create` takes no data symbol and is forwarded; our no-ops
ignore the system's log object it then returns.

Private-extern functions are never forwarded either: no other image can reach them.

A reference between two functions defined in the same object is renamed with them, so that call goes
to our implementation even where the system has the callee. `tests/forward-derivation.sh` lists these
against `tests/fixtures/forward-same-object.txt`. It sees only calls the object makes out of line,
through a relocation: a call the compiler inlined leaves no trace and is not listed. The case to watch
is a caller newer than its callee: our caller then runs on a system that has the callee, and calls ours
instead. As far as availability can be judged:

| Object | Caller -> callee | Judgment |
|---|---|---|
| `mp-time.o` | `clock_gettime` -> `mach_continuous_approximate_time` | acceptable: both arrived in 10.12 |
| `mp-time.o` | `clock_gettime` -> `mach_continuous_time` | acceptable: both arrived in 10.12 |
| `mp-time.o` | `clock_gettime_nsec_np` -> `mach_continuous_approximate_time` | acceptable: both arrived in 10.12 |
| `mp-time.o` | `clock_gettime_nsec_np` -> `mach_continuous_time` | acceptable: both arrived in 10.12 |
| `mp-time.o` | `timespec_get` -> `clock_gettime` | acceptable: on 10.12-10.14 (`timespec_get` is 10.15) MacPorts' `clock_gettime(CLOCK_REALTIME)` runs instead of the system's; it reads the same wall clock and shares no state with it |
| `recaulk-dispatch_modern.o` | `dispatch_block_create_with_qos_class` -> `dispatch_block_create` | acceptable: both arrived in 10.10 |
| `recaulk-ulock.o` | `__ulock_wait` -> `__ulock_wait2` | acceptable: the callee (11.0) is newer than the caller (10.12), so wherever our caller runs the system lacks the callee too |

The trampoline's resolver, `src/forward/resolve.c`, asks `dlsym(RTLD_NEXT, name)` and falls back to the
renamed implementation. On 10.9 neither `RTLD_NEXT` nor a `dlopen("/usr/lib/libSystem.B.dylib",
RTLD_NOLOAD)` handle finds any forwarded name, from a program or a dylib, so the second lookup would
add nothing there; it is not used. `tests/forward-runtime.sh` checks `clock_gettime` both ways, from a
program linking `librecaulk.a` and from one linking `libRecaulkSystem.dylib`. On 10.9 it checks that our
implementation ran; on 10.12 and later, which CI's runners provide, that the system's did. Nothing
checks 10.10 or 10.11.

The renamed `___recaulk_impl_` functions stay global in `librecaulk.a`, since drydock renames symbols
but cannot make them private. `libRecaulkSystem.dylib` is linked with
`-Wl,-unexported_symbol,___recaulk_*`, and a product that links `librecaulk.a` into a dylib of its own
passes the same flag.

## Parity fixture

`tests/fixtures/libSystemWrapper-exports.txt` is the export list of Mavericks Forever's shipped
`libSystemWrapper.dylib`, sha256 `173e9b89c1941b6a1caa7c79c4dd015ae2e2117de9aed42f5d925ed70a8362d7`,
194 symbols:

    nm -gU libSystemWrapper.dylib | awk '{print $3}' | LC_ALL=C sort -u
