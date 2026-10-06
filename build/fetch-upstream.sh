#!/bin/sh
# platform: host-agnostic
# Download + unpack the pinned upstream macports-legacy-support source. Not vendored:
# fetched by tag at build time so Renovate (which edits UPSTREAM_VERSION) drives it.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MLS_ROOT="$(cd "$SELF/.." && pwd)"; export MLS_ROOT
. "$SELF/lib.sh"

U="$(sed -n 's/^REF=v//p' "$MLS_ROOT/components/macports-legacy-support/version")"
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md
#       "Build OUT of the source tree, onto fast local storage" -- CI exports
#       MAVERICKS_BUILD_ROOT itself; this default only covers a plain local run.
: "${MAVERICKS_BUILD_ROOT:=${TMPDIR:-/tmp}/mm-build}"
DEST="${1:-$MAVERICKS_BUILD_ROOT/upstream}"
mkdir -p "$DEST"
tarball="$DEST/v${U}.tar.gz"
url="https://github.com/macports/macports-legacy-support/archive/refs/tags/v${U}.tar.gz"
if [ ! -f "$tarball" ]; then
  tmp="$tarball.tmp.$$"
  curl -fsSL -o "$tmp" "$url"
  mv "$tmp" "$tarball"
fi
src="$DEST/macports-legacy-support-${U}"
[ -d "$src" ] || tar -xzf "$tarball" -C "$DEST"
[ -f "$src/Makefile" ] || { echo "fetch-upstream: no Makefile in $src" >&2; exit 1; }
printf '%s\n' "$src"
