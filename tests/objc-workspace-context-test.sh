#!/bin/sh
# platform: macOS-only -- its actors launch through Launch Services, which needs a logged-in GUI (Aqua) session;
#           the 10.9 guest runs its tests over ssh, with none, so this runs on a Mac's desktop
# spec: tests/c/objc_workspace_context.m selfTest -- locks, stale isolation, archives, missing and partial
#       reports, actor exit and interruption; no app or permission request
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
driver="$(tbin driver)"
if compiling; then
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations -DWORKSPACE_CONTEXT_UNIT_TESTS \
    -DCONTEXT_SOURCE_ID='"unit-controls"' tests/c/objc_workspace_context.m -o "$driver" -framework AppKit -framework Carbon
  check_loads "$driver"
fi
runtime_half
[ "$(launchctl managername)" = Aqua ] || { echo "SKIP: no GUI session here, and Launch Services launches apps only in one"; exit 77; }
X=$(mktemp -d "${TMPDIR:-/tmp}/workspace-context-test.XXXXXX")
X=$(cd "$X" && pwd -P)
trap 'rm -rf "$X"' EXIT
"$driver" self-test "$X"
