#!/bin/sh
# platform: host-agnostic -- builds an x86_64 program on the staged dylib; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Empty collection literals" -- ___NSDictionary0__struct and ___NSArray0__struct, which a newer
#       SDK's clang emits for @{} and @[], are immutable empty collections on 10.9 through
#       libRecaulkSystem.dylib, where Drydock's import redirect sends a binary's CoreFoundation import.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -fno-objc-arc -Wall -Werror tests/c/empty_collections.m -L"$T/lib" -lRecaulkSystem \
    -framework Foundation -o "$(tbin dylib)"
  check_loads "$(tbin dylib)"
fi
runtime_half
fail=0
for v in dylib; do
  # platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it is set where the program is exec'd
  if DYLD_LIBRARY_PATH="$T/lib" "$(tbin "$v")"; then echo "ok $v"; else echo "FAIL $v"; fail=1; fi
done
[ "$fail" = 0 ] && echo "empty-collections OK"
exit "$fail"
