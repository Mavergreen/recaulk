#!/bin/sh
# platform: host-agnostic
# usage: sh build/fetch-cctools.sh OUTDIR -- prints OUTDIR/cctools, holding bin/ld: Mavergreen cctools at
#        components/cctools/version, from its Linux archive on Linux and its pkg on a Mac (CCTOOLS_HOST=linux or mac
#        overrides), each verified against the release's SHA256SUMS
# spec: README.md "The kernel back-fill kext" -- cctools' ld64 writes MH_KEXT_BUNDLE on every host, so the kext
#       links the same on Linux, a modern Mac and 10.9
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 1 ] || { echo "usage: sh build/fetch-cctools.sh OUTDIR" >&2; exit 2; }
out="$1"
mkdir -p "$out"
. "$SELF/msc.sh"
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"
ver="$(tr -d '[:space:]' < "$SELF/../components/cctools/version")"
host="${CCTOOLS_HOST:-}"
if [ -z "$host" ]; then
  case "$(uname -s)" in
    Linux) host=linux ;;
    Darwin) host=mac ;;
    *) echo "fetch-cctools: cctools runs on Linux and on a Mac, not on $(uname -s)" >&2; exit 1 ;;
  esac
fi
case "$host" in
  linux)
    asset="cctools-$ver-linux-x86_64.tar.gz"
    sums="$(mktemp "${TMPDIR:-/tmp}/cctools-sums.XXXXXX")"
    trap 'rm -f "$sums"' EXIT
    shipyard_curl "${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/cctools/releases/download/$ver/SHA256SUMS" "$sums" \
      || { echo "fetch-cctools: could not fetch cctools $ver's SHA256SUMS" >&2; exit 1; }
    sha="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$sums")"
    [ -n "$sha" ] || { echo "fetch-cctools: $asset is not listed in cctools $ver's SHA256SUMS" >&2; exit 1; }
    # platform: cctools' Linux archive holds cctools/ at its root, not the opt/mavergreen/cctools/ prefix shipyard's
    #           fetch_product_tar.sh requires (cctools 1035.1.102-mavericks.2), so it is verified by shipyard and
    #           extracted here; retire this for fetch_product_tar.sh once cctools' archive takes that layout
    cache="${MAVERGREEN_TAR_CACHE:-$HOME/.cache/mavergreen-tars}/cctools/$ver"
    shipyard_fetch_verified "${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/cctools/releases/download/$ver/$asset" \
      "$sha" "$cache" "$asset" >&2
    rm -rf "$out/cctools" "$out/.cctools.x"
    mkdir "$out/.cctools.x"
    tar -xzf "$cache/$asset" -C "$out/.cctools.x"
    [ -d "$out/.cctools.x/cctools" ] || { echo "fetch-cctools: $asset holds no cctools/ at its root" >&2; exit 1; }
    mv "$out/.cctools.x/cctools" "$out/cctools"
    rm -rf "$out/.cctools.x" ;;
  mac) sh "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" cctools "$ver" "$out/cctools" >&2 ;;
  *) echo "fetch-cctools: CCTOOLS_HOST is '$host', not linux or mac" >&2; exit 2 ;;
esac
[ -x "$out/cctools/bin/ld" ] || { echo "fetch-cctools: cctools $ver ($host) gave no bin/ld under $out/cctools" >&2; exit 1; }
printf '%s\n' "$out/cctools"
