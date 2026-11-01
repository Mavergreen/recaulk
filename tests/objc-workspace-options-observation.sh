#!/bin/sh
# platform: macOS-only -- real split-print writer must not satisfy an incomplete observation
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to pinned shipyard scripts}"
D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-options-observation.XXXXXX")
trap 'rm -rf "$D"' EXIT
case "$(uname -m)" in arm64) arch=arm64; floor=11.0 ;; x86_64) arch=x86_64; floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
case "${1:-}" in
  '') [ "$#" = 0 ] || exit 2; source="$ROOT/tests/c/objc_workspace_options_observation.m" ;;
  --mutation-check)
    [ "$#" = 1 ] || exit 2
    cp "$ROOT/tests/c/objc_workspace_options_observation.m" "$ROOT/tests/c/objc_workspace_reference.m" "$D/"
    # Deliberately restore the tempting wrong condition: first print callback
    # implies every file arrived. Only a temporary copy is mutated.
    awk '/for \(NSURL \*url in urls\) ready &= contains/ { print "        ready &= contains(rs, @\"print\", nil);"; next } { print }' "$ROOT/tests/c/objc_workspace_options_reference.m" > "$D/objc_workspace_options_reference.m"
    source="$D/objc_workspace_options_observation.m" ;;
  *) exit 2 ;;
esac
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$source" -o "$D/observation" -framework AppKit -framework Carbon
"$D/observation" "$D"
