#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
. build/lib.sh
tmp="$(mktemp -d "${TMPDIR:-/tmp}/updater-build.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
recaulk_tools

app="$(RECAULK_BUILD="$tmp" sh build/build-updater.sh 20261005.1 2>"$tmp/log")" || { cat "$tmp/log"; echo "FAIL: the updater did not build"; exit 1; }
bin="$app/Contents/MacOS/recaulk-updater"
[ -x "$bin" ] || { echo "FAIL: updater binary missing"; exit 1; }
# platform: otool -L's first line is the binary's own path, which contains "recaulk"; skip it
! "$OTOOL" -L "$bin" | sed 1d | grep -Eq 'librecaulk|libRecaulkSystem' || { echo "FAIL: the updater links the library it updates"; exit 1; }
[ "$("$LIPO" -archs "$bin" | xargs)" = x86_64 ] || { echo "FAIL: the updater is $("$LIPO" -archs "$bin"), not x86_64 only"; exit 1; }
got="$(sed -n '/<key>CFBundleVersion<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$app/Contents/Info.plist")"
[ "$got" = 20261005.1 ] || { echo "FAIL: the updater's CFBundleVersion is '$got', not the version it was built for"; exit 1; }
grep -q -- "-fuse-ld=lld --ld-path=$CL/bin/ld64.lld" "$tmp/updater/CMakeCache.txt" \
  || { echo "FAIL: the updater does not link with clang22's ld64.lld named by --ld-path"; exit 1; }
for k in updater-cmake updater-build-tool; do
  grep -q "^$k=." "$tmp/updater/build-tools.txt" || { echo "FAIL: build-tools.txt beside the updater records no $k"; exit 1; }
done
echo "updater-build OK"
