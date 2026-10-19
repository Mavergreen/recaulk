#!/bin/sh
# platform: macOS-only -- executes x86_64 Mach-O
# The libc++abi back-fills: what a libc++ built on the system's libc++abi (as clang-22's is) and clang 22's
# code generation reference that 10.9's /usr/lib/libc++abi.dylib lacks. The same results are wanted on every
# macOS: on 10.9 Recaulk's run, and where the system has a function the forwarding layer runs the system's.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
D="$(mktemp -d "${TMPDIR:-/tmp}/cxxabi.XXXXXX")"
trap 'rm -rf "$D"' EXIT

# platform: C++11, what 10.9's Apple clang 6 offers and what the 10.9 SDK's libc++ headers were written for;
#           a clang that knows -fchar8_t (Apple clang 10+) adds the char8_t checks in that same mode
std="-std=c++11"
printf 'char8_t c;\n' | /usr/bin/clang++ -std=c++11 -fchar8_t -x c++ -fsyntax-only - 2>/dev/null && std="$std -fchar8_t"
/usr/bin/clang++ $FLAGS -arch x86_64 $std -o "$D/cxxabi" tests/cxx/cxxabi.cpp "$T/lib/librecaulk.a" \
  -framework CoreFoundation -framework Security -framework CoreServices -lobjc -lc++abi \
  || { echo "FAIL: a C++ program using the libc++abi back-fills does not link with librecaulk.a"; exit 1; }
out="$("$D/cxxabi" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
[ "$rc" = 0 ] || { echo "FAIL: cxxabi exited $rc"; exit 1; }
echo "cxxabi OK ($std)"
