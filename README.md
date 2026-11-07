# Recaulk

Modern C library functions for Mac OS X 10.9 Mavericks.

Programs built for newer macOS often call functions 10.9's `libSystem.B.dylib` doesn't have.
Recaulk supplies them:

- `librecaulk.a` for source code
- `libRecaulkSystem.dylib` for binaries
- `librecaulk-cxxabi-exports.a` for one consumer only, libcxx22's `libc++abi.1.dylib` (see C++ exceptions)

When running on newer macOS and a system-provided version of a Recaulk function exists, the system's version is preferred, with a few exceptions.

## How to use

Given source code:

```sh
cc -isystem /usr/local/mavergreen/recaulk/include/recaulk \
   myprogram.c /usr/local/mavergreen/recaulk/lib/librecaulk.a \
   -framework CoreFoundation -framework Security -framework CoreServices -framework IOKit -lobjc
```

(When you're building a dylib, also pass `-Wl,-unexported_symbol,___recaulk_*` to keep Recaulk's internals private.)

(For C++ built against the system's libc++abi, as clang-22's libc++ is, also pass `-lc++abi`: Recaulk fills in the C++ runtime entry points 10.9's libc++abi lacks, and they call the rest of it.)

Given a binary, relink it with [drydock-macho-rewrite](https://github.com/Mavergreen/drydock):

```
dylib  replace  /usr/lib/libSystem.B.dylib  /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib
```

The source headers also adapt two Mavericks API defects: numeric port-zero
`getaddrinfo` requests no longer crash with `AI_NUMERICSERV`, and `fdopendir`
accepts already-open readable directories without requiring search permission.
MacPorts headers remain intact. Where Recaulk wraps a header MacPorts also
provides, MacPorts' copy is staged unmodified under `_recaulk_macports/`, and
Recaulk's header includes it before adding its own declarations.
The directory repair uses libc-owned stream state for both inode ABIs and retains
the original failure for union mounts, whose duplicate filtering needs a separate
implementation. Modern systems still use the forwarded native `fdopendir` first.

Source event loops can include `<recaulk/udp_wait.h>` and use
`__recaulk_kevent_wait_udp` after submitting their normal kqueue changes. Supply
an immutable snapshot of enabled, level-triggered UDP readers and zero-initialized
per-loop fairness state. This wait supplements Mavericks' missing empty-datagram
notifications using `select`, without consuming packets or retaining descriptors.
Other filters remain native. Synthetic UDP events report readiness with `data=0`;
receive the datagram to determine its length. The caller owns descriptor lifetime
and must refresh the snapshot when registrations change.

## Fixes to functions 10.9 has

When Recaulk fixes a defect in a function 10.9's libSystem already exports, the fix reaches both
products. `libRecaulkSystem.dylib` exports it publicly (its source is in `src/overrides/`), and
`librecaulk.a` carries it weak and hidden (`src/backfills/`), so it binds only inside the program or
dylib that links the archive and yields to the dylib's in the one link that has both. Each such name is
listed with its reason in `build/image-local-shadows.txt`, and `tests/rule-backfills-add-only.sh`
holds that list exact. Recaulk's C++ exception rules, its `posix_spawn` and its `pselect` are fixes of
this kind.

## C++ exceptions

C++ code linked with `librecaulk.a` catches pointers and member pointers by the current rules on
10.9 too: a thrown `nullptr` as a member pointer, an `int**` as a `const int* const*`, and a null
derived pointer as a null base pointer, which 10.9's libc++abi gets wrong. The rules hold for the
`catch` clauses of the program or dylib that links Recaulk; other libraries, the system's among
them, keep their own.

`librecaulk-cxxabi-exports.a` is the one archive that deliberately exports names the system
exports: the same two C++ ABI vtables, public. Its one intended consumer is libcxx22's
`libc++abi.1.dylib`, which exports them, so every program that reaches the C++ ABI through libcxx22
gets these rules as well. Link it into nothing else.

## OS version

`os_system_version_get_current_version`, which Swift's runtime calls for `if #available`, is
declared by `<os/system_version.h>` through `include/recaulk`. On 10.9 it reads the version from
`/System/Library/CoreServices/SystemVersion.plist` and returns 0. If it cannot read that file it returns
an `errno` and leaves the version untouched, as it does when the file holds no version it can read. Newer macOS uses its own.

## Security

`SecKeyCreateSignature` takes Apple's `SecKeyAlgorithm` constants and signs on 10.9 with RSA
PKCS#1 v1.5 or X9.62 ECDSA over a SHA-1, SHA-224, SHA-256, SHA-384 or SHA-512 digest. As Apple's
does for a 10.9 key, it signs RSA input no longer than the digest, and refuses ECDSA input that is
not the digest's length. It refuses RSA-PSS, for which 10.9's Security has no primitive, and every
other algorithm, with `errSecParam`, as Apple's does for an algorithm a key does not support.
`SecTrustEvaluateWithError` reports a failure as Apple's does, in `kCFErrorDomainOSStatus` with
codes such as `errSecNotTrusted` and `errSecCertificateExpired`, and `SecTrustCopyCertificateChain`
returns `NULL` for a chain without certificates. Through `include/recaulk`, `<Security/Security.h>`
declares these and the signing constants where the SDK does not. Newer macOS uses its own
implementations.

## Child processes

`posix_spawn_file_actions_addchdir_np` and `posix_spawn_file_actions_addfchdir_np` work on 10.9: the
child starts in the directory they name, and its program path and relative open actions resolve there.
Only the spawning thread's directory changes, and only during the spawn. On 10.9 every chdir action is
taken before the other file actions, wherever it was added among them. To carry them out, programs
linking `librecaulk.a` get Recaulk's `posix_spawn`, `posix_spawnp` and `posix_spawn_file_actions_init`,
`_destroy`, `_addopen`, `_adddup2`, `_addclose` and `_addinherit_np` in place of the system's, inside that program or dylib only; they call
the system's. Newer macOS uses its own chdir actions.

## Vector I/O at an offset

`preadv` and `pwritev` read and write at an offset without moving the file offset, as on macOS 11 and
later, which use their own. On 10.9, a transfer of several buffers over 1 MiB is not atomic: another
writer to the same range can interleave with it.

## Waiting with pselect

10.9's `pselect` sets the signal mask, calls `select`, then restores the mask, as three steps, so a signal
it unblocks that is already pending, or arrives before `select` starts, runs its handler and the wait then
sleeps on. Recaulk's `pselect`, all five of 10.9's symbols for it, never loses such a signal: it returns
`EINTR`, the handler run, as an atomic `pselect` does. Each thread keeps a kqueue that records every signal
posted to the process, from when the image loads (the main thread), the fork (a child) or its first wait
(any other thread); 10.11 and later use their own atomic `pselect`.

Limits on 10.9: a signal handled outside any wait can end the thread's next wait at once with `EINTR`; a
signal sent to one thread (`pthread_kill`) is no better covered than by 10.9's own; one that another
thread handles can end the wait with `EINTR`; one under way as a thread's first wait begins (the main thread's too, in a program linking
`librecaulk.a`: `libRecaulkSystem.dylib` registers it as it loads), or as a fork's child registers its
kqueue, is not seen; and a signal can end a wait a moment before its handler
runs, which it then does as the caller next unblocks it. Where no kqueue can be had (descriptors or
memory exhausted), a wait falls back to 10.9's own `pselect` rather than fail. A program may close the
kqueue's descriptor, as sshd's `closefrom` does: the next wait notices and registers another. Callers
already loop on `EINTR`. `librecaulk.a` must come before libSystem in the link, as clang
puts it; after libSystem, libSystem's `pselect` binds instead.

## Tests

`sh build/build-lib.sh` builds Recaulk with clang22 (`components/clang22/version`, fetched by
`build/fetch-clang22.sh`) on Linux, a modern Mac or 10.9 alike, and `sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"`
runs its tests.
A test that runs an x86_64 program has two halves, and `RECAULK_TEST_PHASE` says which a run does:

- `build`: compile the programs into the build tree's `test-bin/` with clang22 and check them
  (`llvm-nm`, `llvm-otool`, and that each loads only what stock 10.9 has), then stop. Linux and a modern
  Mac do this, and never run an x86_64 program: Rosetta is not a test platform.
- `run`: on 10.9, with no compiler, shipyard or SDK, run the programs `build` made and judge them.
  `RECAULK_BUILD` names the build tree; `RECAULK_INSTALLED`, when set, names the installed Recaulk the
  tests use instead of the build tree's stage, whose libraries must be the same bytes. `tests/guest/run-runtime-tests.sh` runs every such test this
  way, each bounded at 300 s; a hang, a failure or a skip fails.
- `both`: both halves in one run, natively on a 10.9 machine with the Command Line Tools.

Unset, it is `both` on 10.9 and `build` elsewhere. CI builds on Linux, installs the pkg on a real 10.9.5
guest through [mavericks-vm](https://github.com/Mavergreen/mavericks-vm), and runs the `run` half there
against the installed Recaulk.
