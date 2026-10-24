# Recaulk

Modern C library functions for Mac OS X 10.9 Mavericks.

Programs built for newer macOS often call functions 10.9's `libSystem.B.dylib` doesn't have.
Recaulk supplies them:

- `librecaulk.a` for source code
- `libRecaulkSystem.dylib` for binaries

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
