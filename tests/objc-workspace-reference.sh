#!/bin/sh
# platform: macOS-only -- observes the native AppKit launch contract, which 10.9 lacks, using a private fixture
set -eu
umask 077
context_helper="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/helpers/workspace-context.sh"
# spec: tests/README.objc-workspace.md "Actual-method delivery and immutable reference routing" -- the
#       reference root takes only --context runs; preparation, verification, preflight and authorization stay here
if [ -n "${RECAULK_WORKSPACE_REFERENCE_ROOT:-}" ]; then
 if [ "${1:-}" = --context ]; then exec sh "$(dirname "$context_helper")/workspace-reference-root.sh" "$@"; fi
 if [ -n "${RECAULK_WORKSPACE_CONTEXT:-}" ] && { [ "$#" = 0 ] || [ "${1:-}" = --report ]; }; then
  exec sh "$(dirname "$context_helper")/workspace-reference-root.sh" --context "$RECAULK_WORKSPACE_CONTEXT" "$@"
 fi
fi
case "${1:-}" in
  --prepare-context|--verify-context|--context|--authorize-context|--preflight-context) exec sh "$context_helper" "$@" ;;
esac
if [ -n "${RECAULK_WORKSPACE_CONTEXT:-}" ]; then
  if [ "$#" = 0 ]; then exec sh "$context_helper" --context "$RECAULK_WORKSPACE_CONTEXT"; fi
  exec sh "$context_helper" --context "$RECAULK_WORKSPACE_CONTEXT" "$@"
fi
# spec: tests/README.objc-workspace.md "Actual-method delivery and immutable reference routing" -- the
#       CI receipt answers only unconfigured no-argument discovery
if [ "$#" = 0 ] && [ -n "${RECAULK_WORKSPACE_CI_REFERENCE_RECEIPT:-}" ]; then
 exec sh "$(dirname "$context_helper")/workspace-reference-discovery.sh" "$RECAULK_WORKSPACE_CI_REFERENCE_RECEIPT"
fi
# spec: tests/README.objc-workspace.md "Native NSWorkspace reference tests (partial foundation)" -- --report
#       claims a new private directory and rejects symlink components; mkdir without -p claims it atomically
claim_report() {
  case "$1" in /*) output=$1 ;; *) output="$START/$1" ;; esac
  cursor=$output
  while [ "$cursor" != / ] && [ "$cursor" != . ]; do
    [ ! -L "$cursor" ] || { echo "FAIL: symlink report component $cursor" >&2; return 1; }
    cursor=$(dirname "$cursor")
  done
  mkdir -m 700 "$output" || { echo "FAIL: report directory must be new: $output" >&2; return 1; }
  D=$output
}
START=$(pwd -P)
cd "$(dirname "$0")/.."
keep=0
case $# in
  0) D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-reference.XXXXXX") ;;
  2) [ "$1" = --report ] || exit 2; claim_report "$2"; keep=1 ;;
  *) echo 'usage: objc-workspace-reference.sh [--report DIR]' >&2; exit 2 ;;
esac
child=''
interrupt() {
  trap '' INT TERM HUP
  if [ -n "$child" ]; then
    kill -"$1" "$child" 2>/dev/null || :
    wait "$child" 2>/dev/null || :
  else
    # platform: a signal between a background launch and the assignment from $! leaves child unset, so
    #           reap every child before the EXIT trap removes their fixture and report directories
    wait 2>/dev/null || :
  fi
  exit 130
}
trap '_rc=$?; [ "$keep" = 1 ] || rm -rf "$D"; exit $_rc' EXIT
trap 'interrupt INT' INT
trap 'interrupt TERM' TERM
trap 'interrupt HUP' HUP
[ "$(uname -s)" = Darwin ] || { echo 'FAIL: macOS required'; exit 1; }
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the pinned shipyard scripts directory}"
MAVERICKS_ROOT=$(pwd -P)
. build/lib.sh
recaulk_tools
. "$MAVERICKS_ROOT/tests/helpers/native-arch.sh"
printf 'arch=%s\nsdk=%s\n' "$arch" "$SDK" > "$D/build-identity.txt"
for source in tests/c/objc_workspace_reference.m tests/c/objc_workspace_probe_app.m tests/fixtures/workspace-probe-Info.plist.in; do
  [ -f "$source" ] || { echo "FAIL: missing oracle prerequisite $source"; exit 1; }
done
"$CC" $OFLAGS -Wno-deprecated-declarations tests/c/objc_workspace_reference.m -o "$D/reference" -framework AppKit -framework Carbon
"$CC" $OFLAGS tests/c/objc_workspace_probe_app.m -o "$D/probe" -framework AppKit -framework Carbon
status=0
for c in stopped reused multiple mixed new-instance startup reuse-configuration without-activation custom-event custom-reuse invalid-app nil-error nil-error-failure ownership empty empty-custom conflicting-event unknown-key impossible-architecture asynchronous architecture; do
  R="$D/$c"
  [ ! -e "$R" ] || { echo "FAIL: refusing existing case directory $R"; exit 1; }
  mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
  cp "$D/probe" "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
  /usr/bin/plutil -convert xml1 -o "$R/Probe.app/Contents/Info.plist" tests/fixtures/workspace-probe-Info.plist.in
  /usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.workspace-probe.$(basename "$D" | tr -cd 'a-zA-Z0-9').$c" "$R/Probe.app/Contents/Info.plist"
  /usr/bin/codesign --force --sign - "$R/Probe.app" > "$R/codesign.log" 2>&1
  "$D/reference" "$c" "$R/Probe.app" "$R" > "$R/controller.log" 2>&1 &
  child=$!
  rc=0
  wait "$child" || rc=$?
  child=''
  echo "$c: exit $rc"
  [ "$rc" != 77 ] || exit 77
  [ "$rc" = 0 ] || status=1
done
exit "$status"
