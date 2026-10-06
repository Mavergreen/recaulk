#!/bin/sh
# platform: macOS-only -- the upstream Makefile links Mach-O dylibs and sets their ids with install_name_tool
# Cross-build macports-legacy-support to x86_64 / min-10.9 and DESTDIR-install into a
# staging root. Uses the 10.9 SDK ($SDK if set, else mavericks-shipyard's fetch script).
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MLS_ROOT="$(cd "$SELF/.." && pwd)"; export MLS_ROOT
. "$SELF/lib.sh"

U="$(sed -n 's/^REF=v//p' "$MLS_ROOT/components/macports-legacy-support/version")"
P=/usr/local/mavergreen/legacysupport
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md
#       "Build OUT of the source tree, onto fast local storage" -- CI exports
#       MAVERICKS_BUILD_ROOT itself; this default only covers a plain local run.
: "${MAVERICKS_BUILD_ROOT:=${TMPDIR:-/tmp}/mm-build}"
STAGE="${1:-$MAVERICKS_BUILD_ROOT/stage}"
src="$(sh "$SELF/fetch-upstream.sh")"
if [ -z "${SDK:-}" ]; then
  SDK="$(sh "$(msc_scripts)/fetch_sdk.sh")"
fi

flags="-isysroot $SDK -mmacosx-version-min=10.9"
make -C "$src" clean >/dev/null 2>&1 || true
make -C "$src" -j"$(sysctl -n hw.ncpu)" \
  PREFIX="$P" ARCHS=x86_64 SOCURVERSION="$U" SOCOMPATVERSION=1.0.0 \
  CFLAGS="$flags" LDFLAGS="$flags" all 1>&2

rm -rf "$STAGE"; mkdir -p "$STAGE"
make -C "$src" \
  PREFIX="$P" ARCHS=x86_64 SOCURVERSION="$U" SOCOMPATVERSION=1.0.0 \
  DESTDIR="$STAGE" install 1>&2

for f in libMacportsLegacySupport.a libMacportsLegacySupport.dylib; do
  [ -f "$STAGE$P/lib/$f" ] || { echo "build-lib: missing $STAGE$P/lib/$f" >&2; exit 1; }
done
printf '%s\n' "$STAGE"
