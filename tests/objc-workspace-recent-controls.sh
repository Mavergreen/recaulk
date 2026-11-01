#!/bin/sh
# platform: macOS-only -- OPT-IN public Mavericks Recents experiment, NOT a provider
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
if [ "$#" = 0 ] && [ "${RECAULK_WORKSPACE_RECENTS_PROBE:-0}" != 1 ]; then
 echo 'SKIP: explicit private-fixture Recents experiment not configured; not measured'
 exit 77
fi
[ "$#" -ge 1 ] || { echo 'usage: RECAULK_WORKSPACE_RECENTS_PROBE=1 sh tests/objc-workspace-recent-controls.sh NEW_ABSOLUTE_REPORT [CASE...]' >&2; exit 2; }
[ "${RECAULK_WORKSPACE_RECENTS_PROBE:-0}" = 1 ] || { echo 'FAIL: explicit Recents experiment opt-in required' >&2; exit 1; }
D=$1; shift
[ "$#" -gt 0 ] || set -- files legacy-open-files without-recents worker-files print legacy-print
for c do
 case "$c" in default|browser-default|files|legacy-open-files|legacy-print|interleaved|print|hide|without-activation|without-recents|empty|async|worker|worker-files) ;; *) echo 'FAIL: unknown control case' >&2; exit 2 ;; esac
done
case "$D" in /*) ;; *) exit 2 ;; esac
case "$(/usr/bin/sw_vers -productVersion)" in 10.9.*) ;; *) echo 'FAIL: this explicit experiment requires real Mavericks' >&2; exit 1 ;; esac
[ "$(uname -m)" = x86_64 ] || exit 1
[ -z "${DYLD_INSERT_LIBRARIES:-}" ] || { echo 'FAIL: injected libraries' >&2; exit 1; }
: "${SHIPYARD_SCRIPTS:?set pinned shipyard scripts}"
mkdir -m 700 "$D"
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
/usr/bin/clang --version > "$D/build-identity.txt"
printf 'sdk=%s\nscope=approved public private-fixture Recents experiment; no provider\n' "$SDK" >> "$D/build-identity.txt"
for f in objc_workspace_recent_controls.m objc_workspace_recent_list.h objc_workspace_note_recents.h objc_workspace_options_reference.m objc_workspace_reference.m objc_workspace_probe_app.m; do
 cp "$ROOT/tests/c/$f" "$D/"
 shasum -a 256 "$ROOT/tests/c/$f" >> "$D/source-sha256.txt"
done
cp "$0" "$D/entry-point.sh"
/usr/bin/clang -arch x86_64 -isysroot "$SDK" -mmacosx-version-min=10.9 -fno-objc-arc -Wno-deprecated-declarations "$D/objc_workspace_recent_controls.m" -o "$D/floor-control" -framework AppKit -framework Carbon
/usr/bin/clang -arch x86_64 -isysroot "$SDK" -mmacosx-version-min=10.9 -fno-objc-arc "$D/objc_workspace_probe_app.m" -o "$D/probe" -framework AppKit -framework Carbon
status=0
child=
stop() {
 trap '' HUP INT TERM
 if [ -n "$child" ]; then kill -"$1" "$child" 2>/dev/null || :; wait "$child" || :; fi
 exit 1
}
trap 'stop HUP' HUP
trap 'stop INT' INT
trap 'stop TERM' TERM
for c do
 R="$D/$c"
 mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
 cp "$D/probe" "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
 /usr/bin/plutil -convert xml1 -o "$R/Probe.app/Contents/Info.plist" "$ROOT/tests/fixtures/workspace-probe-Info.plist.in"
 /usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.recent-probe.$(basename "$D" | tr -cd 'a-zA-Z0-9').$c" "$R/Probe.app/Contents/Info.plist"
 /usr/bin/codesign --force --sign - "$R/Probe.app" > "$R/signing.log" 2>&1
 shasum -a 256 "$R/Probe.app/Contents/MacOS/WorkspaceProbe" "$R/Probe.app/Contents/Info.plist" > "$R/input-sha256.txt"
 rc=0
 "$D/floor-control" "$c" "$R/Probe.app" "$R" > "$R/controller.json" 2> "$R/controller.log" &
 child=$!
 wait "$child" || rc=$?
 child=
 shasum -a 256 -c "$R/input-sha256.txt" > "$R/input-verification.log"
 echo "$c: $rc"
 [ "$rc" = 0 ] || status=1
done
exit "$status"
