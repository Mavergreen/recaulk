#!/bin/sh
# platform: host-agnostic
set -eu
[ $# -eq 2 ] || { echo "usage: sh build/fetch-drydock.sh VERSION OUTDIR -- prints OUTDIR/drydock-macho-rewrite, from that drydock release's Linux archive on Linux and its pkg on a Mac (DRYDOCK_HOST=linux or mac overrides), verified against its SHA256SUMS" >&2; exit 2; }
ver="$1"; out="$2"
. "$(cd "$(dirname "$0")" && pwd)/msc.sh"
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"
. "$SHIPYARD_SCRIPTS/lib/vercmp.sh"
host="${DRYDOCK_HOST:-}"
if [ -z "$host" ]; then
  case "$(uname -s)" in
    Linux) host=linux ;;
    Darwin) host=mac ;;
    *) echo "fetch-drydock: drydock runs on Linux and on a Mac, not on $(uname -s)" >&2; exit 1 ;;
  esac
fi
case "$host" in
  linux)
    numeric "$ver" && [ "$(ver_cmp "$ver" 0.3.0)" -ge 0 ] \
      || { echo "fetch-drydock: drydock $ver has no Linux archive: drydock publishes drydock-<version>-linux-x86_64.tar.gz from 0.3.0 on" >&2; exit 1; }
    asset="drydock-$ver-linux-x86_64.tar.gz" ;;
  mac) asset="drydock-$ver.pkg" ;;
  *) echo "fetch-drydock: DRYDOCK_HOST is '$host', not linux or mac" >&2; exit 2 ;;
esac
base="${DRYDOCK_RELEASES:-https://github.com/Mavergreen/drydock/releases/download}/v$ver"
[ -d "$out" ] || { echo "no such directory: $out" >&2; exit 1; }
tmp="$(mktemp -d "$out/.fetch.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cache="$out/.cache/v$ver"
listed() { awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$1"; }
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
got=""
if [ -f "$cache/SHA256SUMS" ] && [ -f "$cache/$asset" ]; then
  if [ "$(sha256 "$cache/$asset")" = "$(listed "$cache/SHA256SUMS")" ]; then
    got="$cache/$asset"
  else
    echo "the cached $asset does not match its cached SHA256SUMS; fetching it again" >&2
  fi
fi
if [ -z "$got" ]; then
  rm -rf "$cache"
  shipyard_curl "$base/SHA256SUMS" "$tmp/SHA256SUMS" || { echo "could not fetch $base/SHA256SUMS" >&2; exit 1; }
  sum="$(listed "$tmp/SHA256SUMS")"
  [ -n "$sum" ] || { echo "$asset is not listed in $base/SHA256SUMS" >&2; exit 1; }
  shipyard_curl "$base/$asset" "$tmp/$asset" || { echo "could not fetch $base/$asset" >&2; exit 1; }
  have="$(sha256 "$tmp/$asset")"
  [ "$have" = "$sum" ] || { echo "$asset does not match $base/SHA256SUMS (wanted $sum, got $have)" >&2; exit 1; }
  got="$tmp/$asset"
fi

mkdir "$tmp/p"
if [ "$host" = linux ]; then
  want="drydock-$ver/bin/drydock-macho-rewrite"
  (cd "$tmp/p" && tar -xzf "$got" "$want") || { echo "could not extract $want from $asset (tar's reason above)" >&2; exit 1; }
else
  want=usr/local/mavergreen/drydock/bin/drydock-macho-rewrite
  # platform: guarded macOS-only call -- host is mac only on Darwin or when DRYDOCK_HOST says so
  pkgutil --expand "$got" "$tmp/x"
  n=0
  for info in "$tmp"/x/*/PackageInfo "$tmp"/x/PackageInfo; do
    [ -f "$info" ] || continue
    if grep -q 'identifier="dev.mavergreen.drydock"' "$info"; then
      n=$((n + 1))
      comp="$(dirname "$info")"
    fi
  done
  [ "$n" -eq 1 ] || { echo "$asset has $n components with identifier dev.mavergreen.drydock (want exactly 1)" >&2; exit 1; }
  [ -f "$comp/Payload" ] || { echo "$asset: the dev.mavergreen.drydock component has no Payload" >&2; exit 1; }
  gzip -dc "$comp/Payload" > "$tmp/p.cpio"
  (cd "$tmp/p" && cpio -id --quiet < "$tmp/p.cpio")
fi
[ -f "$tmp/p/$want" ] || { echo "$asset: does not carry $want (the dev.mavergreen.drydock component's tool)" >&2; exit 1; }
chmod +x "$tmp/p/$want"
mv -f "$tmp/p/$want" "$out/drydock-macho-rewrite"
if [ "$got" = "$tmp/$asset" ]; then
  mkdir -p "$cache"
  cp "$tmp/SHA256SUMS" "$tmp/$asset" "$cache/"
fi
printf '%s\n' "$out/drydock-macho-rewrite"
