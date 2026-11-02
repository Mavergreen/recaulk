#!/bin/sh
# platform: macOS-only -- actual backend with recording boundaries; no app/history effects
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
for f in workspace-private.h workspace.m workspace-events.m workspace-recents.m; do
 [ -f "$ROOT/src/objc/$f" ] || { echo "FAIL: missing workspace backend $f"; exit 1; }
done
: "${SHIPYARD_SCRIPTS:?set pinned shipyard scripts}"
D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-backfill-unit.XXXXXX")
trap 'rm -rf "$D"' EXIT
case "$(uname -m)" in arm64) arch=arm64; floor=11.0 ;; x86_64) arch=x86_64; floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$ROOT/tests/c/objc_workspace_backfill_unit.m" "$ROOT/src/objc/workspace.m" "$ROOT/src/objc/workspace-events.m" "$ROOT/src/objc/workspace-recents.m" -o "$D/unit" -framework AppKit -framework Carbon
"$D/unit"
# Run the same recording preference/failure decisions against the PRODUCTION
# helper, not its research predecessor. Macros affect this test TU only.
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations '-DFLOOR_NOTE_HEADER="../../src/objc/workspace-recents.m"' -Drecaulk_workspace_note_recent_files=floorNoteRecentFiles "$ROOT/tests/c/objc_workspace_recent_decisions.m" -o "$D/recents" -framework AppKit -framework Carbon
"$D/recents"
# Compile the default lookup itself (not the per-call recording replacement).
# Query only an impossible PID; self alarm catches a removed polling deadline.
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$ROOT/tests/c/objc_workspace_lookup_deadline.m" "$ROOT/src/objc/workspace-events.m" "$ROOT/src/objc/workspace-recents.m" -o "$D/lookup" -framework AppKit -framework Carbon
"$D/lookup"
