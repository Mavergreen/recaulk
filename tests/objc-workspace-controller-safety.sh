#!/bin/sh
# platform: host-agnostic -- builds the launch oracle with clang22; on 10.9 it must refuse hostile outputs and fixture identity before the method (RECAULK_TEST_PHASE)
set -eu
umask 077
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macos.sh
ref="$(tbin reference)"
if compiling; then
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations tests/c/objc_workspace_reference.m -o "$ref" \
    -framework AppKit -framework Carbon
  check_loads "$ref"
fi
runtime_half
ROOT=$(pwd -P)
X=$(mktemp -d "${TMPDIR:-/tmp}/workspace-controller-safety.XXXXXX")
X=$(cd "$X" && pwd -P)
trap 'rm -rf "$X"' EXIT
for scenario in existing-output symlink-output symlink-report symlink-events symlink-executable wrong-report wrong-id remote-app remote-file-app existing-mixed symlink-mixed hardlink-mixed; do
 R="$X/$scenario"
 mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
 printf '#!/bin/sh\nexit 1\n' > "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
 chmod 700 "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
 cp "$ROOT/tests/fixtures/workspace-probe-Info.plist.in" "$R/Probe.app/Contents/Info.plist"
 plist_buddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
 plist_buddy -c "Set :CFBundleIdentifier org.mavergreen.controller-safety.$scenario" "$R/Probe.app/Contents/Info.plist"
 app="$R/Probe.app"; report=$R; probe_case=stopped
 printf 'unrelated sentinel\n' > "$X/victim"
 case "$scenario" in
  existing-mixed) probe_case=mixed; cp "$X/victim" "$R/sentinel.txt" ;;
  symlink-mixed) probe_case=mixed; ln -s "$X/victim" "$R/sentinel.txt" ;;
  hardlink-mixed) probe_case=mixed; ln "$X/victim" "$R/sentinel.txt" ;;
  existing-output) cp "$X/victim" "$R/controller.json" ;;
  symlink-output) ln -s "$X/victim" "$R/controller.json" ;;
  symlink-report) ln -s "$R" "$X/report-link"; report="$X/report-link" ;;
  symlink-events) rmdir "$R/events"; ln -s "$X" "$R/events" ;;
  symlink-executable) mv "$R/Probe.app/Contents/MacOS/WorkspaceProbe" "$X/executable"; ln -s "$X/executable" "$R/Probe.app/Contents/MacOS/WorkspaceProbe" ;;
  wrong-report) plist_buddy -c "Set :WorkspaceProbeReportDirectory $X" "$R/Probe.app/Contents/Info.plist" ;;
  wrong-id) plist_buddy -c 'Set :CFBundleIdentifier com.example.unrelated' "$R/Probe.app/Contents/Info.plist" ;;
  remote-app) app='https://workspace-probe.invalid/not-a-file-app' ;;
  remote-file-app) app="file://workspace-probe.invalid$R/Probe.app" ;;
 esac
 rc=0
 "$ref" "$probe_case" "$app" "$report" > "$X/log" 2>&1 || rc=$?
 [ "$rc" = 1 ] || { echo "FAIL: $scenario exit=$rc (must fail before method absence)"; exit 1; }
 [ "$(/usr/bin/stat -f %z "$X/victim")" = 19 ] || { echo "FAIL: $scenario wrote unrelated file"; exit 1; }
 if [ "$scenario" = existing-output ]; then cmp "$X/victim" "$R/controller.json" || { echo 'FAIL: existing output overwritten'; exit 1; }; fi
 case "$scenario" in *-mixed) cmp "$X/victim" "$R/sentinel.txt" || { echo 'FAIL: mixed input overwritten'; exit 1; } ;; esac
 echo "$scenario: refused without unrelated writes"
done
