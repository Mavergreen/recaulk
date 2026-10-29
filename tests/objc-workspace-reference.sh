#!/bin/sh
# platform: macOS-only -- observes the native AppKit launch contract using a private fixture
set -eu
cd "$(dirname "$0")/.."
keep=0
case $# in
  0) D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-reference.XXXXXX") ;;
  2) [ "$1" = --report ] || exit 2; mkdir -p "$2"; D=$(cd "$2" && pwd -P); keep=1 ;;
  *) echo 'usage: objc-workspace-reference.sh [--report DIR]' >&2; exit 2 ;;
esac
trap '[ "$keep" = 1 ] || rm -rf "$D"' EXIT
[ "$(uname -s)" = Darwin ] || { echo 'FAIL: macOS required'; exit 1; }
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the pinned shipyard scripts directory}"
arch=$(uname -m)
case "$arch" in arm64) floor=11.0 ;; x86_64) floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
printf 'arch=%s\nsdk=%s\n' "$arch" "$SDK" > "$D/build-identity.txt"
# Contract tests below require exact sentinel argv/environment, delivered URLs,
# and equality of returned PID with the process whose event log contains them.
for source in tests/c/objc_workspace_reference.m tests/c/objc_workspace_probe_app.m tests/fixtures/workspace-probe-Info.plist.in; do
  [ -f "$source" ] || { echo "FAIL: missing oracle prerequisite $source"; exit 1; }
done
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations tests/c/objc_workspace_reference.m -o "$D/reference" -framework AppKit -framework Carbon
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc tests/c/objc_workspace_probe_app.m -o "$D/probe" -framework AppKit -framework Carbon
status=0
for c in stopped reused multiple mixed new-instance startup reuse-configuration without-activation custom-event invalid-app nil-error ownership empty conflicting-event unknown-key impossible-architecture asynchronous architecture; do
  R="$D/$c"
  [ ! -e "$R" ] || { echo "FAIL: refusing existing case directory $R"; exit 1; }
  mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
  cp "$D/probe" "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
  /usr/bin/plutil -convert xml1 -o "$R/Probe.app/Contents/Info.plist" tests/fixtures/workspace-probe-Info.plist.in
  /usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.workspace-probe.$(basename "$D" | tr -cd 'a-zA-Z0-9').$c" "$R/Probe.app/Contents/Info.plist"
  /usr/bin/codesign --force --sign - "$R/Probe.app" > "$R/codesign.log" 2>&1
  rc=0
  "$D/reference" "$c" "$R/Probe.app" "$R" > "$R/controller.log" 2>&1 || rc=$?
  echo "$c: exit $rc"
  [ "$rc" != 77 ] || exit 77
  [ "$rc" = 0 ] || status=1
done
exit "$status"
