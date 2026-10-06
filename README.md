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

Given a binary, relink it with [drydock-macho-rewrite](https://github.com/Mavergreen/drydock):

```
dylib  replace  /usr/lib/libSystem.B.dylib  /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib
```
