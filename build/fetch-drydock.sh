#!/bin/sh
# platform: macOS-only -- curl, shasum and pkgutil, as 10.9 and the CI Macs provide
set -eu
[ $# -eq 2 ] || { echo "usage: sh build/fetch-drydock.sh VERSION OUTDIR -- prints OUTDIR/drydock-macho-rewrite, from that drydock release's pkg, verified against its SHA256SUMS" >&2; exit 2; }
ver="$1"; out="$2"
asset="drydock-$ver.pkg"
want=usr/local/mavergreen/drydock/bin/drydock-macho-rewrite
base="${DRYDOCK_RELEASES:-https://github.com/Mavergreen/drydock/releases/download}/v$ver"
[ -d "$out" ] || { echo "no such directory: $out" >&2; exit 1; }
tmp="$(mktemp -d "$out/.fetch.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cache="$out/.cache/v$ver"
listed() { awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$1"; }
pkg=""
if [ -f "$cache/SHA256SUMS" ] && [ -f "$cache/$asset" ]; then
  if [ "$(shasum -a 256 "$cache/$asset" | cut -d' ' -f1)" = "$(listed "$cache/SHA256SUMS")" ]; then
    pkg="$cache/$asset"
  else
    echo "the cached $asset does not match its cached SHA256SUMS; fetching it again" >&2
  fi
fi
if [ -z "$pkg" ]; then
  rm -rf "$cache"
  curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS" || { echo "could not fetch $base/SHA256SUMS" >&2; exit 1; }
  curl -fsSL "$base/$asset" -o "$tmp/$asset" || { echo "could not fetch $base/$asset" >&2; exit 1; }
  sum="$(listed "$tmp/SHA256SUMS")"
  [ -n "$sum" ] || { echo "$asset is not listed in $base/SHA256SUMS" >&2; exit 1; }
  got="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
  [ "$got" = "$sum" ] || { echo "$asset does not match $base/SHA256SUMS (wanted $sum, got $got)" >&2; exit 1; }
  pkg="$tmp/$asset"
fi

pkgutil --expand "$pkg" "$tmp/x"
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
mkdir "$tmp/p"
gzip -dc "$comp/Payload" > "$tmp/p.cpio"
(cd "$tmp/p" && cpio -id --quiet < "$tmp/p.cpio")
[ -f "$tmp/p/$want" ] || { echo "$asset: the dev.mavergreen.drydock component does not carry $want" >&2; exit 1; }
chmod +x "$tmp/p/$want"
mv -f "$tmp/p/$want" "$out/drydock-macho-rewrite"
if [ "$pkg" = "$tmp/$asset" ]; then
  mkdir -p "$cache"
  cp "$tmp/SHA256SUMS" "$tmp/$asset" "$cache/"
fi
printf '%s\n' "$out/drydock-macho-rewrite"
