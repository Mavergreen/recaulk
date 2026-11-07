#!/bin/sh
# platform: host-agnostic
# spec: tests/README.objc-workspace.md -- discovery checks only the pinned historical receipt; it measures nothing
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
fail() { echo "FAIL: reference discovery receipt $*" >&2; exit 1; }
[ "$#" = 1 ] || fail 'requires exactly one explicit receipt'
for source in tests/c/objc_workspace_reference.m tests/c/objc_workspace_context.m tests/c/objc_workspace_probe_app.m tests/fixtures/workspace-probe-Info.plist.in tests/helpers/workspace-context.sh tests/fixtures/workspace-reference-source.sha256; do
 [ -f "$ROOT/$source" ] && [ ! -L "$ROOT/$source" ] || fail 'source prerequisites invalid'
done
F=$1; case "$F" in /*) ;; *) F=$PWD/$F ;; esac
[ -f "$F" ] || fail 'missing'
p=$F
while [ "$p" != / ]; do [ ! -L "$p" ] || fail 'symlink input'; p=$(dirname "$p"); done
# spec: tests/fixtures/workspace-native-reference-receipt.json -- only this exact receipt, never counts or partial facts
cmp -s "$F" "$ROOT/tests/fixtures/workspace-native-reference-receipt.json" || fail 'stale, partial or unrecognized pin'
echo 'SKIP: not-measured-on-this-host; pinned complete native21 reference receipt verified (15 normative,6 observed-only); NOT a current-host/oracle/provider pass'
exit 77
