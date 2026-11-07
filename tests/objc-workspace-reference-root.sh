#!/bin/sh
# platform: macOS-only -- the frozen verifier it dispatches to (409f958, pinned by hash) reads sw_vers and gives macOS-only refusals; nothing compiles or launches
# spec: tests/README.objc-workspace.md "Actual-method delivery and immutable reference routing" -- only the exact
#       frozen clone takes context runs; verification stays local and configured discovery is routed too
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
[ -f "$ROOT/tests/helpers/workspace-reference-root.sh" ] || { echo 'FAIL: frozen-root adapter absent'; exit 1; }
: "${SHIPYARD_SCRIPTS:?set pinned shipyard scripts}"
D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-reference-root.XXXXXX")
D=$(cd "$D" && pwd -P)
git clone --no-hardlinks --no-checkout "$ROOT" "$D/frozen" > "$D/clone.log" 2>&1
git -C "$D/frozen" checkout --detach 409f9589d9586955265779fb7d814bfe6e0dc945 >> "$D/clone.log" 2>&1
run() {
 name=$1; source=$2; shift 2
 rc=0
 RECAULK_WORKSPACE_REFERENCE_ROOT="$source" sh "$ROOT/tests/objc-workspace-reference.sh" "$@" > "$D/$name.log" 2>&1 || rc=$?
 [ "$rc" = 1 ] || { echo "FAIL: $name exit$rc, expected verifier failure before launch"; exit 1; }
 [ ! -e "$D/report" ] || { echo 'FAIL: rejected invocation created launch report'; exit 1; }
}
run exact "$D/frozen" --context "$D/no-context" --report "$D/report"
grep -q 'verified frozen source; delegating context run' "$D/exact.log"
grep -Eq 'stable Automation context requires macOS|context must be caller-owned/private' "$D/exact.log"
run self "$ROOT" --context "$D/no-context" --report "$D/report"
grep -q 'FAIL: frozen reference' "$D/self.log"
run missing "$D/no-source" --context "$D/no-context" --report "$D/report"
grep -q 'FAIL: frozen reference' "$D/missing.log"
ln -s "$D/frozen" "$D/link"
run symlink "$D/link" --context "$D/no-context" --report "$D/report"
grep -q 'FAIL: frozen reference' "$D/symlink.log"
printf '\n/* modified private test clone */\n' >> "$D/frozen/tests/c/objc_workspace_probe_app.m"
run modified "$D/frozen" --context "$D/no-context" --report "$D/report"
grep -q 'FAIL: frozen reference' "$D/modified.log"
git -C "$D/frozen" checkout -- tests/c/objc_workspace_probe_app.m
git -C "$D/frozen" -c user.name=Fixture -c user.email=fixture@invalid commit --allow-empty -m 'Private wrong-HEAD fixture' > "$D/commit.log"
run wrong-head "$D/frozen" --context "$D/no-context" --report "$D/report"
grep -q 'FAIL: frozen reference' "$D/wrong-head.log"
run verify-local "$D/no-source" --verify-context "$D/no-context"
if grep -q 'FAIL: frozen reference' "$D/verify-local.log"; then echo 'FAIL: verify-local was refused as a frozen reference'; exit 1; fi
rc=0
RECAULK_WORKSPACE_CONTEXT="$D/no-context" RECAULK_WORKSPACE_REFERENCE_ROOT="$ROOT" sh "$ROOT/tests/objc-workspace-reference.sh" > "$D/discovery.log" 2>&1 || rc=$?
[ "$rc" = 1 ] && grep -q 'FAIL: frozen reference' "$D/discovery.log"
echo "PASS: real frozen dispatcher/verifier, source/head/path/symlink rejection, local verification and discovery routing; no launch. Evidence: $D"
echo 'Boundary: valid stable-context/native delivery and changed-app rejection require modern native run; not asserted here.'
