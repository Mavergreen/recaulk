#!/bin/sh
# platform: macOS-only -- builds an x86_64 program against libRecaulkSystem.dylib; runs it on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
[ -f "$T/lib/libRecaulkSystem.dylib" ] || { echo "FAIL: libRecaulkSystem.dylib missing: the link failed"; exit 1; }
if compiling; then
  /usr/bin/clang -isysroot "$SDK" -arch x86_64 -mmacosx-version-min=10.9 -isystem "$T/include/recaulk" \
    -o "$(tbin load)" tests/c/load.c -L"$T/lib" -lRecaulkSystem
  otool -L "$(tbin load)" | grep -q '/usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib' \
    || { echo "FAIL: the program does not name the absolute install name"; exit 1; }
  check_loads "$(tbin load)"
fi
runtime_half
# platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it must be set where the
#           test program is exec'd.
out="$(DYLD_LIBRARY_PATH="$T/lib" "$(tbin load)")" || { echo "FAIL: the program exited non-zero"; exit 1; }
[ "$out" = "recaulk-load ok" ] || { echo "FAIL: output was '$out'"; exit 1; }
echo "load OK"
