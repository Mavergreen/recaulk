#!/bin/sh
# platform: host-agnostic -- the receipt gate, report claim and frozen-root refusal it drives are shell checks that run before objc-workspace-reference.sh builds or launches anything
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
[ -f "$ROOT/tests/helpers/workspace-reference-discovery.sh" ] || { echo 'FAIL: native-reference discovery receipt gate absent'; exit 1; }
unset RECAULK_WORKSPACE_CONTEXT RECAULK_WORKSPACE_REFERENCE_ROOT RECAULK_WORKSPACE_CI_REFERENCE_RECEIPT
D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-discovery.XXXXXX")
D=$(cd "$D" && pwd -P)
F=$ROOT/tests/fixtures/workspace-native-reference-receipt.json
run() {
 name=$1; want=$2; receipt=$3; shift 3
 rc=0; RECAULK_WORKSPACE_CI_REFERENCE_RECEIPT="$receipt" sh "$ROOT/tests/objc-workspace-reference.sh" "$@" > "$D/$name.log" 2>&1 || rc=$?
 [ "$rc" = "$want" ] || { echo "FAIL: discovery $name exit$rc expected$want"; exit 1; }
}
run pinned 77 "$F"
grep -q 'not-measured-on-this-host' "$D/pinned.log"
run missing 1 "$D/no-receipt"
printf '{"schema":1}\n' > "$D/partial.json"
run partial 1 "$D/partial.json"
awk '{sub(/409f9589d9586955265779fb7d814bfe6e0dc945/,"0000000000000000000000000000000000000000"); print}' "$F" > "$D/stale.json"
run stale 1 "$D/stale.json"
ln -s "$F" "$D/link.json"
run symlink 1 "$D/link.json"
# spec: tests/objc-workspace-reference.sh claim_report -- a direct run is not discovery; an existing report fails before any build
run direct 1 "$F" --report "$D"
if grep -q 'not-measured-on-this-host' "$D/direct.log"; then echo 'FAIL: a direct run reported itself as discovery'; exit 1; fi
rc=0
RECAULK_WORKSPACE_CONTEXT="$D/no-context" RECAULK_WORKSPACE_REFERENCE_ROOT="$ROOT" RECAULK_WORKSPACE_CI_REFERENCE_RECEIPT="$F" sh "$ROOT/tests/objc-workspace-reference.sh" > "$D/configured.log" 2>&1 || rc=$?
{ [ "$rc" = 1 ] && ! grep -q 'not-measured-on-this-host' "$D/configured.log"; } || { echo "FAIL: configured run: exit $rc, or it reported itself as discovery"; exit 1; }
# spec: tests/helpers/workspace-reference-discovery.sh -- a pinned receipt cannot hide missing source prerequisites
mkdir -p "$D/incomplete/tests/helpers" "$D/incomplete/tests/fixtures"
cp "$ROOT/tests/objc-workspace-reference.sh" "$D/incomplete/tests/"
cp "$ROOT/tests/helpers/workspace-reference-discovery.sh" "$D/incomplete/tests/helpers/"
cp "$F" "$D/incomplete/tests/fixtures/"
rc=0; RECAULK_WORKSPACE_CI_REFERENCE_RECEIPT="$F" sh "$D/incomplete/tests/objc-workspace-reference.sh" > "$D/prerequisite.log" 2>&1 || rc=$?
{ [ "$rc" = 1 ] && ! grep -q 'not-measured-on-this-host' "$D/prerequisite.log"; } || { echo "FAIL: prerequisite run: exit $rc, or it reported itself as discovery"; exit 1; }
echo "PASS: pinned complete receipt only omits unconfigured no-argument discovery; missing/stale/partial/symlink inputs and prerequisites fail; direct/configured runs never inherit omission. Evidence: $D"
