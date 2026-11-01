#!/bin/sh
# platform: macOS-only -- recording boundary; never edits shared history/preferences
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to pinned shipyard scripts}"
D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-recent-decisions.XXXXXX")
trap 'rm -rf "$D"' EXIT
case "$(uname -m)" in arm64) arch=arm64; floor=11.0 ;; x86_64) arch=x86_64; floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
source="$ROOT/tests/c/objc_workspace_recent_decisions.m"
case "${1:-}" in
 '') [ "$#" = 0 ] || exit 2 ;;
 --mutation-check)
  [ "$#" = 1 ] || exit 2
  cp "$source" "$D/"
  # Real helper, deliberately broken ONLY in a temporary copy. The recording
  # boundary prevents any mutation run from touching shared lists.
  awk '{sub(/if \(ok \&\& maximum > 0\)/,"if (ok)"); print}' "$ROOT/tests/c/objc_workspace_note_recents.h" > "$D/objc_workspace_note_recents.h"
  source="$D/objc_workspace_recent_decisions.m" ;;
 *) exit 2 ;;
esac
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$source" -o "$D/decisions" -framework AppKit -framework Carbon
"$D/decisions"
