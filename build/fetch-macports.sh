#!/bin/sh
# platform: host-agnostic
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"

[ $# -eq 1 ] || { echo "usage: sh build/fetch-macports.sh DEST -- prints DEST/macports-legacy-support-<version>, freshly extracted from the pinned MacPorts commit" >&2; exit 2; }
repo="$(macports_pin REPO)"
digest="$(macports_pin DIGEST)"
sha="$(macports_pin TARBALL_SHA256)"
src="$1/macports-legacy-support-$(macports_version)"
sh "$SHIPYARD_SCRIPTS/fetch_pinned_source.sh" "$repo" "$digest" "$sha" "$src" 1>&2 || {
  echo "fetch-macports: the MacPorts source did not verify -- if the MacPorts pin moved, run sh build/pin-source-tarball.sh and commit components/macports-legacy-support/version" >&2
  exit 1
}
printf '%s\n' "$src"
