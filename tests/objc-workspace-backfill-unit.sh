#!/bin/sh
# platform: host-agnostic -- builds the provider's backend with recording boundaries for x86_64; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: tests/README.objc-workspace.md "Unregistered backend unit gate" -- no app launch, history edit or registration
set -eu
umask 077
cd "$(dirname "$0")/.."
. tests/helpers/built.sh

if compiling; then
  for f in workspace-private.h workspace.m workspace-events.m workspace-recents.m; do
    [ -f "src/objc/$f" ] || { echo "FAIL: missing workspace backend $f"; exit 1; }
  done
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations tests/c/objc_workspace_backfill_unit.m \
    src/objc/workspace.m src/objc/workspace-events.m src/objc/workspace-recents.m -o "$(tbin unit)" \
    -framework AppKit -framework Carbon
  # spec: tests/README.objc-workspace.md "Unregistered backend unit gate" -- the PRODUCTION Recents helper, not the research one
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations '-DFLOOR_NOTE_HEADER="../../src/objc/workspace-recents.m"' \
    -D__recaulk_workspace_note_recent_files=floorNoteRecentFiles tests/c/objc_workspace_recent_decisions.m \
    -o "$(tbin recents)" -framework AppKit -framework Carbon
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations tests/c/objc_workspace_lookup_deadline.m \
    src/objc/workspace-events.m src/objc/workspace-recents.m -o "$(tbin lookup)" -framework AppKit -framework Carbon
  check_loads "$(tbin unit)" "$(tbin recents)" "$(tbin lookup)"
fi
runtime_half
"$(tbin unit)"
"$(tbin recents)"
"$(tbin lookup)"
echo "objc-workspace-backfill-unit OK"
