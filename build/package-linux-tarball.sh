#!/bin/sh
# platform: host-agnostic -- needs GNU tar (TAR= names one), as ed25519's package-tar.sh does
#   usage: VERSION=V [OUT=DIR] sh build/package-linux-tarball.sh
#          Writes OUT/recaulk-V-linux-x86_64.tar.gz (default OUT: dist) and prints its path: opt/mavergreen/recaulk/
#          holding build-lib.sh's staged lib/, include/ and share/, and a static Linux bin/recaulk-materialize; owned
#          by 0:0, every mtime the commit's (SOURCE_DATE_EPOCH wins), ustar entries sorted by name, gzipped by the
#          pinned stevedore, so one tree always gives the same bytes.
# spec: README.md "Materializing an SDK view" -- the .pkg's tree, for porters building Mavericks targets on Linux
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"
: "${VERSION:?package-linux-tarball: VERSION required}"
B="$(recaulk_build_dir)"
T="$B/stage/usr/local/mavergreen/recaulk"
[ -f "$T/lib/librecaulk.a" ] || { echo "package-linux-tarball: no $T; run build/build-lib.sh first" >&2; exit 1; }
OUT="${OUT:-$MAVERICKS_ROOT/dist}"
MT="$(cd "$MAVERICKS_ROOT" && sh "$SHIPYARD_SCRIPTS/source-date-epoch.sh")"
SD="$(sh "$SHIPYARD_SCRIPTS/fetch_stevedore.sh")"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
W="$(mktemp -d "$OUT/package-linux-tarball.XXXXXX")"
trap 'rm -rf "$W"' EXIT
P="$W/root/opt/mavergreen/recaulk"
mkdir -p "$P/bin"
cp -R "$T/lib" "$T/include" "$T/share" "$P/"
RECAULK_VERSION="$VERSION" sh "$SELF/build-materialize.sh" linux "$P/bin/recaulk-materialize"
chmod 755 "$P/bin/recaulk-materialize"
find "$W/root" -type d -exec chmod 755 {} +
find "$W/root" -type f ! -path '*/bin/*' -exec chmod 644 {} +
"${TAR:-tar}" --sort=name --format=ustar --owner=0 --group=0 --numeric-owner --mtime="@$MT" \
  -C "$W/root" -cf "$W/recaulk.tar" opt
out="$OUT/recaulk-$VERSION-linux-x86_64.tar.gz"
"$SD" gzip < "$W/recaulk.tar" > "$W/out.tar.gz"
mv "$W/out.tar.gz" "$out"
printf '%s\n' "$out"
