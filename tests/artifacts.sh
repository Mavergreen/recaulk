#!/bin/sh
# platform: macOS-only -- otool and lipo inspect the built Mach-O files
set -eu
# platform: ls and sort order names by the locale's collation, which ignores case in macOS 26's en_US.UTF-8 and compares bytes in 10.9's
LC_ALL=C
export LC_ALL
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
dylib="$T/lib/libRecaulkSystem.dylib"
[ -f "$dylib" ] || { echo "FAIL: $dylib missing: the link failed"; exit 1; }
fail=0
bad() { echo "FAIL: $*"; fail=1; }

for f in librecaulk.a libRecaulkSystem.dylib; do
  [ "$(lipo -info "$T/lib/$f" | sed -n 's/.*: //p' | xargs)" = x86_64 ] || bad "$f is not x86_64-only"
done
otool -l "$dylib" | grep -A2 LC_VERSION_MIN_MACOSX | grep -q 'version 10.9' || bad "dylib min is not 10.9"
[ "$(otool -D "$dylib" | sed -n 2p)" = /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib ] \
  || bad "install name is $(otool -D "$dylib" | sed -n 2p)"
otool -L "$dylib" | sed -n 2p | grep -q 'compatibility version 1.0.0, current version 1356.0.0' \
  || bad "versions are not 1.0.0 / 1356.0.0: $(otool -L "$dylib" | sed -n 2p)"
otool -l "$dylib" | grep -A2 LC_REEXPORT_DYLIB | grep -q 'name /usr/lib/libSystem.B.dylib' \
  || bad "no LC_REEXPORT_DYLIB of /usr/lib/libSystem.B.dylib"
got="$(otool -L "$dylib" | sed '1,2d' | sed 's/^[[:space:]]*//; s/ (.*//; s|.*/||; s|\.framework.*||' | sort | tr '\n' ' ')"
want="CoreFoundation CoreGraphics CoreServices CoreVideo Security libSystem.B.dylib libobjc.A.dylib "
[ "$got" = "$want" ] || bad "linked libraries are '$got', want '$want'"
[ -f "$T/include/recaulk/MacportsLegacySupport.h" ] || bad "include/recaulk/MacportsLegacySupport.h missing"
[ "$(ls "$T/lib" | tr '\n' ' ')" = "libRecaulkSystem.dylib librecaulk.a " ] || bad "lib holds: $(ls "$T/lib" | tr '\n' ' ')"
stray="$(cd "$B/stage" && find . -mindepth 1 -not -path ./usr -not -path ./usr/local -not -path ./usr/local/mavergreen \
  -not -path ./usr/local/mavergreen/recaulk -not -path './usr/local/mavergreen/recaulk/*' | head -5)"
[ -z "$stray" ] || bad "stage holds files outside usr/local/mavergreen/recaulk: $stray"
[ "$fail" = 0 ] && echo "artifacts OK"
exit $fail
