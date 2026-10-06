#!/bin/sh
# platform: macOS-only -- compiles against the 10.9 SDK
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }

d="$(mktemp -d "${TMPDIR:-/tmp}/headers.XXXXXX")"
trap 'rm -rf "$d"' EXIT
{
  echo '#include <MacportsLegacySupport.h>'
  echo '#include <os/lock.h>'
  echo '#include <time.h>'
  (cd src/include && find . -type f | sed 's|^\./||' | LC_ALL=C sort) | sed 's|.*|#include <&>|'
  echo 'int main(void){return 0;}'
} > "$d/all.c"
[ -n "$(find src/include -type f 2>/dev/null)" ] || bad "src/include holds no headers"
/usr/bin/clang $FLAGS -arch x86_64 -Wall -Werror -I"$T/include/recaulk" -c "$d/all.c" -o "$d/all.o" || bad "the headers do not compile together"

mpinc="$W/macports-legacy-support-$(macports_version)/include"
[ -d "$mpinc" ] || bad "no MacPorts include tree at $mpinc to compare against"
for h in $(cd src/include && find . -type f | sed 's|^\./||'); do
  [ ! -e "$mpinc/$h" ] || bad "src/include/$h would overwrite MacPorts' header"
done
[ "$fail" = 0 ] && echo "headers OK"
exit $fail
