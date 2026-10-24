#!/bin/sh
# platform: macOS-only -- executes x86_64 Mach-O
# spec: src/backfills/cxxabi_*.c -- what 10.9's libc++abi lacks for clang-22's libc++ and codegen; the same results
#       on every macOS, from Recaulk on 10.9 and from the system where it has the function.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
D="$(mktemp -d "${TMPDIR:-/tmp}/cxxabi.XXXXXX")"
trap 'rm -rf "$D"' EXIT

. tests/helpers/cxx.sh
/usr/bin/clang++ $FLAGS -arch x86_64 $CXX_STD -o "$D/cxxabi" tests/cxx/cxxabi.cpp "$T/lib/librecaulk.a" \
  -framework CoreFoundation -framework Security -framework CoreServices -lobjc -lc++abi \
  || { echo "FAIL: a C++ program using the libc++abi back-fills does not link with librecaulk.a"; exit 1; }
out="$("$D/cxxabi" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
[ "$rc" = 0 ] || { echo "FAIL: cxxabi exited $rc"; exit 1; }
echo "cxxabi OK ($CXX_STD)"
