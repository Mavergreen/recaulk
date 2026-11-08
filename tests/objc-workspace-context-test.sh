#!/bin/sh
# platform: host-agnostic -- builds the stable runner's unit controls with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
#           in a logged-in GUI (Aqua) session, since its actors launch through Launch Services
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
# platform: guarded macOS-only call -- launchctl runs only once uname -s says Darwin
if [ "$(uname -s)" = Darwin ] && [ "$(launchctl managername)" = Aqua ]; then :; else echo "SKIP: no GUI session here, and Launch Services launches apps only in one"; exit 77; fi
X=$(mktemp -d "${TMPDIR:-/tmp}/workspace-context-test.XXXXXX")
X=$(cd "$X" && pwd -P)
trap 'rm -rf "$X"' EXIT
"$driver" self-test "$X"
