#!/bin/sh
# platform: host-agnostic
#   usage: build-updater.sh VERSION     prints recaulk-updater.app, built x86_64 for 10.9 with clang22
#          (build/fetch-clang22.sh), configured by the host's cmake on Linux and shipyard-cmake on a Mac; writes
#          the build tools that built it to build-tools.txt beside the app
set -eu
MAVERICKS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export MAVERICKS_ROOT
. "$MAVERICKS_ROOT/build/lib.sh"
VER="${1:?usage: build-updater.sh VERSION}"
if [ "$(uname -s)" = Linux ]; then SC="$(command -v cmake)" || { echo "build-updater: no cmake on PATH" >&2; exit 1; }
else SC="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"; fi
SY="$(dirname "$SHIPYARD_SCRIPTS")"
recaulk_tools
W="$(recaulk_build_dir)"
rm -rf "$W/updater"
"$SC" -S "$MAVERICKS_ROOT" -B "$W/updater" -DCMAKE_TOOLCHAIN_FILE="$SY/MavericksToolchain.cmake" \
  -DMavericksShipyard_DIR="$SY" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OBJC_COMPILER="$CC" -DCMAKE_OBJC_COMPILER_TARGET=x86_64-apple-macos10.9 \
  -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld --ld-path=$CL/bin/ld64.lld" \
  -DRECAULK_VERSION="$VER" >&2
"$SC" --build "$W/updater" --target recaulk-updater >&2
sh "$MAVERICKS_ROOT/build/build-tools.sh" "$W/updater" updater > "$W/updater/build-tools.txt"
echo "$W/updater/recaulk-updater.app"
