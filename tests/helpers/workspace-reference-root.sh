#!/bin/sh
# platform: macOS-only -- exact frozen oracle dispatcher, never prepare/authorize
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
fail() { echo "FAIL: frozen reference $*" >&2; exit 1; }
[ "${1:-}" = --context ] || fail 'delegation is for context runs only'
F=${RECAULK_WORKSPACE_REFERENCE_ROOT:-}
case "$F" in /*) ;; *) fail 'requires an absolute independent clone' ;; esac
[ -d "$F" ] || fail 'root missing'
physical=$(CDPATH= cd -- "$F" && pwd -P) || fail 'root inaccessible'
[ "${F%/}" = "$physical" ] || fail 'root path is not canonical (symlink/dot component)'
F=$physical
[ "$F" != "$ROOT" ] || fail 'self-recursion'
[ "$(git -C "$F" rev-parse HEAD)" = 409f9589d9586955265779fb7d814bfe6e0dc945 ] || fail 'wrong source commit'
# spec: tests/fixtures/workspace-reference-source.sha256 -- the six pinned inputs are real files, never symlinks
for file in tests/c/objc_workspace_reference.m tests/c/objc_workspace_context.m tests/c/objc_workspace_probe_app.m tests/fixtures/workspace-probe-Info.plist.in tests/helpers/workspace-context.sh tests/objc-workspace-reference.sh; do
 p=$F/$file
 [ -f "$p" ] || fail 'input missing'
 while [ "$p" != "$F" ]; do [ ! -L "$p" ] || fail 'symlink input'; p=$(dirname "$p"); done
done
(cd "$F" && /usr/bin/shasum -a 256 -c "$ROOT/tests/fixtures/workspace-reference-source.sha256") >&2 || fail 'source/input hash mismatch'
echo 'verified frozen source; delegating context run to original verifier (no preparation/authorization)' >&2
unset RECAULK_WORKSPACE_REFERENCE_ROOT
exec sh "$F/tests/objc-workspace-reference.sh" "$@"
