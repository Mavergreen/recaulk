#!/bin/sh
# platform: host-agnostic
# usage: sh build/build-materialize.sh host|mac|linux OUTFILE
#        sh build/build-materialize.sh unit OUTFILE TEST_MAIN.c   (host build, TEST_MAIN.c in place of main.c)
#        host:  for this machine, to run the tests (clang22 for the host arch on Darwin, ${HOST_CC:-cc} elsewhere)
#        mac:   universal x86_64 (10.9) + arm64 (11.0), what the .pkg ships
#        linux: static x86_64, what the Linux tarball ships (${HOST_CC:-cc} -static)
# spec: .superpowers/specs/2026-11-24-recaulk-materialize-design.md "Delivery"
set -eu
[ $# -eq 2 ] || { [ $# -eq 3 ] && [ "$1" = unit ]; } \
  || { echo "build-materialize: usage: build-materialize.sh host|mac|linux OUTFILE | unit OUTFILE TEST_MAIN.c" >&2; exit 2; }
mode="$1" out="$2"
SELF="$(cd "$(dirname "$0")" && pwd)"
SRCS="main.c util.c json.c sha256.c apply.c publish.c"
srcs=""
for s in $SRCS; do [ -f "$SELF/../src/materialize/$s" ] && srcs="$srcs $SELF/../src/materialize/$s"; done
if [ "$mode" = unit ]; then
  srcs="$(printf '%s\n' $srcs | grep -v '/main\.c$' | tr '\n' ' ') $(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
  mode=host
fi
warn="-std=c99 -O2 -Wall -Wextra -Werror -D_XOPEN_SOURCE=700 -D_DARWIN_C_SOURCE"
ver="-DRECAULK_VERSION=\"${RECAULK_VERSION:-dev}\""
mkdir -p "$(dirname "$out")"
mac_slice() {  # $1 arch, $2 floor, $3 sdk, $4 out
  "$CC" --no-default-config --target="$1-apple-macos$2" -mmacosx-version-min="$2" -isysroot "$3" $warn "$ver" $srcs -o "$4"
}
case "$mode" in
  host)
    if [ "$(uname -s)" = Darwin ]; then
      . "$SELF/lib.sh"; recaulk_tools
      SDK="${SDK:-$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")}"
      # platform: the host's own arch, so the tests run it natively on 10.9, Intel and Apple Silicon alike
      case "$(uname -m)" in arm64) mac_slice arm64 11.0 "$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)" "$out" ;;
                            *) mac_slice x86_64 10.9 "$SDK" "$out" ;; esac
    else
      # shellcheck disable=SC2086
      ${HOST_CC:-cc} $warn "$ver" $srcs -o "$out"
    fi ;;
  mac)
    . "$SELF/lib.sh"; recaulk_tools
    SDK="${SDK:-$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")}"
    mac_slice x86_64 10.9 "$SDK" "$out.x86_64"
    mac_slice arm64 11.0 "$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)" "$out.arm64"
    "$LIPO" -create "$out.x86_64" "$out.arm64" -output "$out"
    rm -f "$out.x86_64" "$out.arm64" ;;
  linux)
    # shellcheck disable=SC2086
    ${HOST_CC:-cc} -static $warn "$ver" $srcs -o "$out" ;;
  *) echo "build-materialize: unknown mode $mode" >&2; exit 2 ;;
esac
