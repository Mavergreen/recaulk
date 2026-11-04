#!/bin/sh
# platform: macOS-only -- prepare/verify a disposable ungranted pair, never request permission
set -eu
umask 077
# Prepares and checks a context from the CURRENT source; never the frozen verifier.
unset RECAULK_WORKSPACE_REFERENCE_ROOT RECAULK_WORKSPACE_CONTEXT RECAULK_WORKSPACE_CI_REFERENCE_RECEIPT
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
# The 10.9 declaration-only host is covered by the context unit test, not this
# modern no-prompt Automation integration prerequisite.
version=$(sw_vers -productVersion); major=${version%%.*}; rest=${version#*.}; minor=${rest%%.*}
if [ "$major" -lt 11 ] && { [ "$major" != 10 ] || [ "$minor" -lt 14 ]; }; then exit 77; fi
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-context-prepare.XXXXXX")
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
entry="$ROOT/tests/objc-workspace-reference.sh"
sh "$entry" --prepare-context "$T/context"
cp "$T/context/apps.sha256" "$T/before"
sh "$entry" --verify-context "$T/context"
sh "$entry" --verify-context "$T/context"
cmp "$T/before" "$T/context/apps.sha256"
[ ! -e "$T/context/request.json" ] && [ ! -e "$T/context/response.json" ] || exit 1
# Refuse a held lock without launching/requesting anything.
mkdir "$T/context/.run-lock"
rc=0; sh "$entry" --context "$T/context" --report "$T/locked-report" > "$T/locked.log" 2>&1 || rc=$?
[ "$rc" = 1 ] && [ ! -e "$T/context/request.json" ] || exit 1
rmdir "$T/context/.run-lock"
# Newly prepared unique pair: no permission request. Nonzero is cannot-measure.
rc=0; sh "$entry" --context "$T/context" --report "$T/ungranted-report" > "$T/ungranted.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || { echo 'FAIL: ungranted context was not a failing prerequisite'; exit 1; }
grep -q 'ungranted context' "$T/ungranted-report/response.json" || exit 1
[ ! -e "$T/context/.run-lock" ] && [ ! -e "$T/context/request.json" ] || exit 1
# Verification still works; failed preflight must archive logs, not leave stale
# event records that would make an eventual authorized run impossible.
sh "$entry" --verify-context "$T/context"
[ -z "$(ls -A "$T/context/events")" ] || exit 1
# Auto-discovery invokes the selected reference with no arguments. Generated
# internal reports must use physical paths, even under the usual lexical TMPDIR.
rc=0; RECAULK_WORKSPACE_CONTEXT="$T/context" sh "$entry" > "$T/selected.log" 2>&1 || rc=$?
[ "$rc" = 1 ] && grep -q 'ungranted context' "$T/selected.log" || { echo 'FAIL: selected no-argument path did not reach nonprompt prerequisite'; exit 1; }
# Existing result is never replaced.
find "$T/ungranted-report" -type f -exec /usr/bin/shasum -a 256 {} \; | LC_ALL=C sort > "$T/report-before"
rc=0; sh "$entry" --context "$T/context" --report "$T/ungranted-report" > "$T/existing.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || exit 1
find "$T/ungranted-report" -type f -exec /usr/bin/shasum -a 256 {} \; | LC_ALL=C sort > "$T/report-after"
cmp "$T/report-before" "$T/report-after"
# Signed input mutation is detected without executing the mutated actor.
printf '\n' >> "$T/context/Sender.app/Contents/Info.plist"
rc=0; sh "$entry" --verify-context "$T/context" > "$T/tampered.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || exit 1
echo 'disposable context: repeated verification, lock/output refusal, ungranted no-prompt failure and tamper refusal pass'
