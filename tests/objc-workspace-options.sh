#!/bin/sh
# platform: macOS-only -- additional private-fixture observations of the native launch method, which 10.9 lacks; no consent requests
set -eu
umask 077
START=$(pwd -P)
cd "$(dirname "$0")/.."
mode=
keep=0
case "${1:-}" in --native) mode=native; shift ;; --self-test) mode=self; shift ;; esac
# spec: tests/README.objc-workspace.md "Additional native option measurements (not provider acceptance)" -- native
#       mode is opt-in: it launches private fixture apps, and its default, files, interleaved and print
#       cases add the probe app and fixture documents to Recent Items, the positive control for without-recents
if [ -z "$mode" ]; then
  [ "$#" -gt 0 ] || [ "${RECAULK_WORKSPACE_OPTIONS_NATIVE:-0}" = 1 ] || {
    echo 'SKIP: native options launches (fixture apps, Recent Items) are opt-in: --native or RECAULK_WORKSPACE_OPTIONS_NATIVE=1; not measured'
    exit 77
  }
  mode=native
fi
case $# in
  0) D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-options.XXXXXX") ;;
  2)
    [ "$1" = --report ] || exit 2
    case "$2" in /*) D=$2 ;; *) D="$START/$2" ;; esac
    cursor=$D
    while [ "$cursor" != / ]; do
      [ ! -L "$cursor" ] || { echo 'FAIL: symlink report component' >&2; exit 1; }
      cursor=$(dirname "$cursor")
    done
    mkdir -m 700 "$D" || { echo 'FAIL: report directory must be new' >&2; exit 1; }
    keep=1 ;;
  *) echo 'usage: objc-workspace-options.sh [--native|--self-test] [--report NEW_DIR]' >&2; exit 2 ;;
esac
child=''
interrupt() {
  trap '' INT TERM HUP
  if [ -n "$child" ]; then kill -"$1" "$child" 2>/dev/null || :; fi
  wait 2>/dev/null || :
  exit 130
}
trap '[ "$keep" = 1 ] || rm -rf "$D"' EXIT
trap 'interrupt INT' INT
trap 'interrupt TERM' TERM
trap 'interrupt HUP' HUP
[ "$(uname -s)" = Darwin ] || { echo 'FAIL: macOS required'; exit 1; }
for source in tests/c/objc_workspace_options_reference.m tests/c/objc_workspace_reference.m tests/c/objc_workspace_probe_app.m tests/fixtures/workspace-probe-Info.plist.in; do
  [ -f "$source" ] || { echo "FAIL: missing options prerequisite $source" >&2; exit 1; }
done
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to pinned shipyard scripts}"
MAVERICKS_ROOT=$(pwd -P)
. build/lib.sh
recaulk_tools
. "$MAVERICKS_ROOT/tests/helpers/native-arch.sh"
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
printf 'arch=%s\nsdk=%s\nsource_head=%s\n' "$arch" "$SDK" "$(git rev-parse HEAD)" > "$D/build-identity.txt"
"$CC" --version >> "$D/build-identity.txt"
shasum -a 256 tests/objc-workspace-options.sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" tests/c/objc_workspace_options_reference.m tests/c/objc_workspace_reference.m tests/c/objc_workspace_probe_app.m tests/fixtures/workspace-probe-Info.plist.in > "$D/source-sha256.txt"
"$CC" $OFLAGS -Wno-deprecated-declarations tests/c/objc_workspace_options_reference.m -o "$D/options-reference" -framework AppKit -framework Carbon
"$CC" $OFLAGS tests/c/objc_workspace_probe_app.m -o "$D/probe" -framework AppKit -framework Carbon
fixture() {
  R="$D/$1"
  mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
  cp "$D/probe" "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
  /usr/bin/plutil -convert xml1 -o "$R/Probe.app/Contents/Info.plist" tests/fixtures/workspace-probe-Info.plist.in
  /usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.workspace-options.$(basename "$D" | tr -cd 'a-zA-Z0-9').$1" "$R/Probe.app/Contents/Info.plist"
  # spec: tests/README.objc-workspace.md "Additional native option measurements (not provider acceptance)" -- ad-hoc
  #       signing applies only to the fresh private fixture, never the approved stable pair
  /usr/bin/codesign --force --sign - "$R/Probe.app" > "$R/codesign.log" 2>&1
  shasum -a 256 "$R/Probe.app/Contents/MacOS/WorkspaceProbe" "$R/Probe.app/Contents/Info.plist" > "$R/input-sha256.txt"
}
run_case() {
  rc=0
  "$D/options-reference" "$1" "$2" "$R" > "$R/controller.log" 2>&1 &
  child=$!
  wait "$child" || rc=$?
  child=''
  shasum -a 256 -c "$R/input-sha256.txt" > "$R/input-verification.log"
}
if [ "$mode" = self ]; then
  # spec: tests/README.objc-workspace.md "Additional native option measurements (not provider acceptance)" -- every
  #       unsafe input below fails before the launch call or absence handling, even on a modern host
  fixture unknown
  run_case not-a-case "$R/Probe.app"
  [ "$rc" = 1 ] || { echo 'FAIL: unknown case accepted'; exit 1; }
  fixture invalid-utf8
  invalid=$(printf '\377')
  run_case default "$invalid"
  [ "$rc" = 1 ] || { echo 'FAIL: malformed UTF-8 must fail cleanly before launch'; exit 1; }
  fixture unrelated-private-app
  unrelated_app="$R/Probe.app"
  fixture wrong-app
  run_case default "$unrelated_app"
  [ "$rc" = 1 ] || { echo 'FAIL: uncontrolled app accepted'; exit 1; }
  fixture sentinel
  printf 'preserve sentinel\n' > "$R/one.txt"
  run_case files "$R/Probe.app"
  [ "$rc" = 1 ] && [ "$(head -1 "$R/one.txt")" = 'preserve sentinel' ] || { echo 'FAIL: existing sentinel accepted or modified'; exit 1; }
  printf 'preserve sentinel target\n' > "$D/sentinel-target"
  for link in symlink hardlink; do
    fixture "sentinel-$link"
    if [ "$link" = symlink ]; then ln -s "$D/sentinel-target" "$R/one.txt"; else ln "$D/sentinel-target" "$R/one.txt"; fi
    run_case files "$R/Probe.app"
    [ "$rc" = 1 ] && [ "$(head -1 "$D/sentinel-target")" = 'preserve sentinel target' ] || { echo 'FAIL: linked sentinel accepted or modified'; exit 1; }
  done
  fixture linked-output
  printf 'preserve target\n' > "$D/target"
  ln -s "$D/target" "$R/controller.json"
  run_case default "$R/Probe.app"
  [ "$rc" = 1 ] && [ "$(head -1 "$D/target")" = 'preserve target' ] || { echo 'FAIL: linked report accepted or modified'; exit 1; }
  fixture existing-output
  printf 'preserve output\n' > "$R/controller.json"
  run_case default "$R/Probe.app"
  [ "$rc" = 1 ] && [ "$(head -1 "$R/controller.json")" = 'preserve output' ] || { echo 'FAIL: existing report accepted or modified'; exit 1; }
  echo 'PASS: options controller rejects unsafe inputs without invoking launch'
  exit 0
fi
status=0
for c in default files interleaved print hide without-activation without-recents empty async worker nil-urls nil-configuration non-url-element relative-url; do
  fixture "$c"
  run_case "$c" "$R/Probe.app"
  echo "$c: exit $rc"
  # spec: tests/README.objc-workspace.md "Additional native option measurements (not provider acceptance)" -- a
  #       Mavericks exit 77 is only API absence, which must never hide an earlier failure
  [ "$rc" != 77 ] || { [ "$status" = 0 ] || exit 1; exit 77; }
  [ "$rc" = 0 ] || status=1
done
exit "$status"
