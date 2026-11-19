#!/bin/sh
# platform: host-agnostic -- links x86_64 programs against librecaulk.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Compiler builtins" -- a program that brings its own compiler-rt (Zig's compiler_rt.c.o) links
#       with librecaulk.a in either order, even when the archive is searched first, and its own builtins win;
#       otherwise Recaulk's convert exactly, rounding to nearest, ties to even.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -c tests/c/half_float_own_builtins.c -o "$(tbin own.o)"
  # platform: -u loads the archive's members for these names before the program's object is read, as an
  #   early librecaulk.a on the link line does
  "$CC" $FLAGS -arch x86_64 -Wl,-u,___extendhfsf2 -Wl,-u,___truncsfhf2 "$T/lib/librecaulk.a" "$(tbin own.o)" \
    -o "$(tbin archive-first)" || { echo "FAIL: librecaulk.a first, then a program with its own half-float builtins, does not link"; exit 1; }
  "$CC" $FLAGS -arch x86_64 "$(tbin own.o)" "$T/lib/librecaulk.a" -o "$(tbin archive-last)" \
    || { echo "FAIL: a program with its own half-float builtins, then librecaulk.a, does not link"; exit 1; }
  "$CC" $FLAGS -arch x86_64 -Wall -Werror tests/c/half_float_values.c "$T/lib/librecaulk.a" -o "$(tbin values)"
  check_loads "$(tbin archive-first)" "$(tbin archive-last)" "$(tbin values)"
fi
runtime_half
"$(tbin archive-first)"
"$(tbin archive-last)"
"$(tbin values)"
