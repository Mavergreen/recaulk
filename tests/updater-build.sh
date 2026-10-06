#!/bin/sh
# platform: macOS-only -- otool inspects the built updater's linked libraries
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d "${TMPDIR:-/tmp}/updater-build.XXXXXX")"
SC="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"; [ -x "$SC" ] || { echo "no shipyard-cmake -- skipping" >&2; exit 77; }
. build/msc.sh || { echo "msc.sh could not locate shipyard -- skipping" >&2; exit 77; }
[ -f "$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake" ] \
  || { echo "the shipyard at $SHIPYARD_SCRIPTS predates MavericksToolchain.cmake -- install the current shipyard pkg" >&2; exit 1; }

B="$tmp/updater"
"$SC" -S . -B "$B" -DCMAKE_OBJC_COMPILER=/usr/bin/clang -DRECAULK_VERSION=20261005.1 \
  -DCMAKE_TOOLCHAIN_FILE="$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake" >/dev/null
"$SC" --build "$B" --target recaulk-updater >/dev/null
bin="$B/recaulk-updater.app/Contents/MacOS/recaulk-updater"
[ -x "$bin" ] || { echo "updater binary missing"; exit 1; }
# platform: otool -L's first line is the binary's own path, which contains "recaulk"; skip it
! otool -L "$bin" | sed 1d | grep -Eq 'librecaulk|libRecaulkSystem' || { echo "updater links the library it updates"; exit 1; }
echo "updater-build OK"
