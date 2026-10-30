#!/bin/sh
# platform: macOS-only -- standalone oracle refuses hostile outputs and mismatched fixture identity
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the pinned shipyard scripts directory}"
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-controller-safety.XXXXXX")
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
arch=$(uname -m)
case "$arch" in arm64) floor=11.0 ;; x86_64) floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$ROOT/tests/c/objc_workspace_reference.m" -o "$T/reference" -framework AppKit -framework Carbon
for scenario in existing-output symlink-output symlink-report symlink-events symlink-executable wrong-report wrong-id remote-app remote-file-app; do
 R="$T/$scenario"
 mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
 printf '#!/bin/sh\nexit 1\n' > "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
 chmod 700 "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
 cp "$ROOT/tests/fixtures/workspace-probe-Info.plist.in" "$R/Probe.app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.controller-safety.$scenario" "$R/Probe.app/Contents/Info.plist"
 app="$R/Probe.app"; report=$R
 printf 'unrelated sentinel\n' > "$T/victim"
 case "$scenario" in
  existing-output) cp "$T/victim" "$R/controller.json" ;;
  symlink-output) ln -s "$T/victim" "$R/controller.json" ;;
  symlink-report) ln -s "$R" "$T/report-link"; report="$T/report-link" ;;
  symlink-events) rmdir "$R/events"; ln -s "$T" "$R/events" ;;
  symlink-executable) mv "$R/Probe.app/Contents/MacOS/WorkspaceProbe" "$T/executable"; ln -s "$T/executable" "$R/Probe.app/Contents/MacOS/WorkspaceProbe" ;;
  wrong-report) /usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $T" "$R/Probe.app/Contents/Info.plist" ;;
  wrong-id) /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.unrelated' "$R/Probe.app/Contents/Info.plist" ;;
  remote-app) app='https://workspace-probe.invalid/not-a-file-app' ;;
  remote-file-app) app="file://workspace-probe.invalid$R/Probe.app" ;;
 esac
 rc=0
 "$T/reference" stopped "$app" "$report" > "$T/log" 2>&1 || rc=$?
 [ "$rc" = 1 ] || { echo "FAIL: $scenario exit=$rc (must fail before method absence)"; exit 1; }
 [ "$(/usr/bin/stat -f %z "$T/victim")" = 19 ] || { echo "FAIL: $scenario wrote unrelated file"; exit 1; }
 if [ "$scenario" = existing-output ]; then cmp "$T/victim" "$R/controller.json" || { echo 'FAIL: existing output overwritten'; exit 1; }; fi
 echo "$scenario: refused without unrelated writes"
done
