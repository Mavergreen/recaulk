#!/bin/sh
# platform: macOS-only -- prepares a disposable Sender/Probe pair for the no-prompt Automation API of macOS 10.14+, and exits 77 below that (10.9 included); never requests permission
# spec: tests/README.objc-workspace.md "Stable app-hosted context" -- a context from the current source
#       verifies repeatedly, refuses a held lock and an existing report, fails ungranted without a prompt,
#       archives a failed preflight and refuses a tampered signed input
set -eu
umask 077
unset RECAULK_WORKSPACE_REFERENCE_ROOT RECAULK_WORKSPACE_CONTEXT RECAULK_WORKSPACE_CI_REFERENCE_RECEIPT
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
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
mkdir "$T/context/.run-lock"
rc=0; sh "$entry" --context "$T/context" --report "$T/locked-report" > "$T/locked.log" 2>&1 || rc=$?
[ "$rc" = 1 ] && [ ! -e "$T/context/request.json" ] || exit 1
rmdir "$T/context/.run-lock"
rc=0; sh "$entry" --context "$T/context" --report "$T/ungranted-report" > "$T/ungranted.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || { echo 'FAIL: ungranted context was not a failing prerequisite'; exit 1; }
grep -q 'ungranted context' "$T/ungranted-report/response.json" || exit 1
[ ! -e "$T/context/.run-lock" ] && [ ! -e "$T/context/request.json" ] || exit 1
sh "$entry" --verify-context "$T/context"
[ -z "$(ls -A "$T/context/events")" ] || exit 1
rc=0; RECAULK_WORKSPACE_CONTEXT="$T/context" sh "$entry" > "$T/selected.log" 2>&1 || rc=$?
[ "$rc" = 1 ] && grep -q 'ungranted context' "$T/selected.log" || { echo 'FAIL: selected no-argument path did not reach nonprompt prerequisite'; exit 1; }
find "$T/ungranted-report" -type f -exec /usr/bin/shasum -a 256 {} \; | LC_ALL=C sort > "$T/report-before"
rc=0; sh "$entry" --context "$T/context" --report "$T/ungranted-report" > "$T/existing.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || exit 1
find "$T/ungranted-report" -type f -exec /usr/bin/shasum -a 256 {} \; | LC_ALL=C sort > "$T/report-after"
cmp "$T/report-before" "$T/report-after"
printf '\n' >> "$T/context/Sender.app/Contents/Info.plist"
rc=0; sh "$entry" --verify-context "$T/context" > "$T/tampered.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || exit 1
echo 'disposable context: repeated verification, lock/output refusal, ungranted no-prompt failure and tamper refusal pass'
