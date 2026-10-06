#!/bin/sh
# platform: macOS-only -- executes x86_64 Mach-O
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
[ -f "$T/lib/libRecaulkSystem.dylib" ] || { echo "FAIL: libRecaulkSystem.dylib missing: the link failed"; exit 1; }
D="$(mktemp -d "${TMPDIR:-/tmp}/load.XXXXXX")"
trap 'rm -rf "$D"' EXIT
/usr/bin/clang -isysroot "$SDK" -arch x86_64 -mmacosx-version-min=10.9 -isystem "$T/include/recaulk" \
  -o "$D/load" tests/c/load.c -L"$T/lib" -lRecaulkSystem
otool -L "$D/load" | grep -q '/usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib' \
  || { echo "FAIL: the program does not name the absolute install name"; exit 1; }
# platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it must be set where the
#           test program is exec'd.
out="$(DYLD_LIBRARY_PATH="$T/lib" "$D/load")" || { echo "FAIL: the program exited non-zero"; exit 1; }
[ "$out" = "recaulk-load ok" ] || { echo "FAIL: output was '$out'"; exit 1; }
echo "load OK"
