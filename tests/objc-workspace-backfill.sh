#!/bin/sh
# platform: macOS-only -- explicit REAL Mavericks provider delivery; no Automation requests
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
if [ "$#" = 0 ]; then
 # Default suite on 10.9: build this tree's companion and run the floor
 # controls through the real method (private fixture apps, URL-only, so only
 # Recent Applications is touched). Elsewhere the method is native: unmeasured.
 case "$(/usr/bin/sw_vers -productVersion)" in 10.9.*) ;; *) echo 'SKIP: real backfill delivery runs only on Mavericks; not measured'; exit 77 ;; esac
 : "${SHIPYARD_SCRIPTS:?select pinned shipyard scripts}"
 T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-backfill.XXXXXX")
 sh "$ROOT/build/build-objc.sh" "$T/stage" "$T/work" > "$T/builder.log" 2>&1 || { echo "FAIL: companion build; see $T/builder.log"; exit 1; }
 set -- --prefix "$T/stage" --report "$T/report" --floor-controls-only
fi
{ [ "$#" = 4 ] || { [ "$#" = 5 ] && [ "$5" = --floor-controls-only ]; }; } && [ "$1" = --prefix ] && [ "$3" = --report ] || { echo 'usage: objc-workspace-backfill.sh --prefix PREFIX --report NEW_ABSOLUTE_DIR [--floor-controls-only]' >&2; exit 2; }
only_floor=0; [ "$#" != 5 ] || only_floor=1
P=$2; D=$4
case "$P:$D" in /*:/*) ;; *) exit 2 ;; esac
[ -f "$ROOT/tests/c/objc_workspace_backfill_integration.m" ] || { echo 'FAIL: actual-method integration driver absent'; exit 1; }
case "$(/usr/bin/sw_vers -productVersion)" in 10.9.*) ;; *) echo 'FAIL: actual Mavericks required'; exit 1 ;; esac
[ -z "${DYLD_INSERT_LIBRARIES:-}${DYLD_FRAMEWORK_PATH:-}${DYLD_LIBRARY_PATH:-}" ] || exit 1
[ -f "$P/lib/librecaulk-objc.a" ] || exit 1
: "${SHIPYARD_SCRIPTS:?select pinned shipyard scripts}"
cursor=$D
while [ "$cursor" != / ]; do [ ! -L "$cursor" ] || { echo 'FAIL: symlink report component'; exit 1; }; cursor=$(dirname "$cursor"); done
mkdir -m 700 "$D"
# The archive must be built from THIS tree; a stale prefix would otherwise turn
# an older provider's run into this commit's evidence.
/usr/bin/plutil -convert xml1 -o "$D/objc-providers.plist" "$P/share/recaulk/objc-providers.json"
/usr/libexec/PlistBuddy -c 'Print :build:source_inputs_receipt' "$D/objc-providers.plist" | grep -v '  generated/' | grep . > "$D/source-inputs-receipt.txt"
[ "$(/usr/libexec/PlistBuddy -c 'Print :build:architecture' "$D/objc-providers.plist")" = x86_64 ] || { echo 'FAIL: prefix archive is not x86_64'; exit 1; }
(cd "$ROOT" && /usr/bin/shasum -a 256 -c "$D/source-inputs-receipt.txt") > "$D/source-inputs-verification.log" 2>&1 || { echo 'FAIL: prefix archive was not built from this tree'; cat "$D/source-inputs-verification.log"; exit 1; }
[ "$(/usr/bin/shasum -a 256 "$P/lib/librecaulk-objc.a" | cut -d' ' -f1)" = "$(/usr/libexec/PlistBuddy -c 'Print :build:archive_sha256' "$D/objc-providers.plist")" ] || { echo 'FAIL: prefix archive does not match its manifest'; exit 1; }
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
/usr/bin/clang --version > "$D/compiler.txt"
/usr/bin/shasum -a 256 "$P/lib/librecaulk-objc.a" "$ROOT/tests/c/objc_workspace_reference.m" "$ROOT/tests/c/objc_workspace_options_reference.m" "$ROOT/tests/c/objc_workspace_probe_app.m" "$ROOT/tests/fixtures/workspace-probe-Info.plist.in" "$ROOT/tests/c/objc_workspace_backfill_integration.m" > "$D/input-sha256.txt"
/usr/bin/clang -arch x86_64 -isysroot "$SDK" -mmacosx-version-min=10.9 -fno-objc-arc -Wno-deprecated-declarations "$ROOT/tests/c/objc_workspace_backfill_integration.m" -o "$D/controller" "$P/lib/librecaulk-objc.a" -Wl,-u,___recaulk_objc_activate -framework AppKit -framework Carbon
/usr/bin/clang -arch x86_64 -isysroot "$SDK" -mmacosx-version-min=10.9 -fno-objc-arc -Wno-deprecated-declarations "$ROOT/tests/c/objc_workspace_backfill_integration.m" -o "$D/negative-controller" -framework AppKit -framework Carbon
/usr/bin/clang -arch x86_64 -isysroot "$SDK" -mmacosx-version-min=10.9 -fno-objc-arc "$ROOT/tests/c/objc_workspace_probe_app.m" -o "$D/probe-x64" -framework AppKit -framework Carbon
/usr/bin/clang -arch i386 -isysroot "$SDK" -mmacosx-version-min=10.9 -fno-objc-arc "$ROOT/tests/c/objc_workspace_probe_app.m" -o "$D/probe-i386" -framework AppKit -framework Carbon
/usr/bin/lipo -create "$D/probe-x64" "$D/probe-i386" -output "$D/probe"
/usr/bin/lipo -info "$D/probe" > "$D/probe-slices.txt"
fixture() {
 R=$D/$1
 mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
 cp "$D/probe" "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
 /usr/bin/plutil -convert xml1 -o "$R/Probe.app/Contents/Info.plist" "$ROOT/tests/fixtures/workspace-probe-Info.plist.in"
 /usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.workspace.backfill.$(basename "$D" | tr -cd 'a-zA-Z0-9').$1" "$R/Probe.app/Contents/Info.plist"
 /usr/bin/codesign --force --sign - "$R/Probe.app" > "$R/signing.log" 2>&1
 /usr/bin/shasum -a 256 "$R/Probe.app/Contents/MacOS/WorkspaceProbe" "$R/Probe.app/Contents/Info.plist" > "$R/input-sha256.txt"
}
fixture negative-activation
rc=0; "$D/negative-controller" stopped "$R/Probe.app" "$R" > "$R/controller.log" 2>&1 || rc=$?
printf '%s\n' "$rc" > "$R/controller.exit"
[ "$rc" = 77 ] || { echo "FAIL: negative actual missing-method control exit$rc, expected77"; exit 1; }
echo 'EXPECTED RED: root/body omitted; actual method absent (77), not a compatibility pass'
child=
stop() { trap '' HUP INT TERM; if [ -n "$child" ]; then kill -"$1" "$child" 2>/dev/null || :; wait "$child" || :; fi; exit 1; }
trap 'stop HUP' HUP; trap 'stop INT' INT; trap 'stop TERM' TERM
status=0
original_cases='stopped reused multiple mixed new-instance startup reuse-configuration without-activation custom-event custom-reuse invalid-app nil-error nil-error-failure ownership empty empty-custom conflicting-event unknown-key impossible-architecture asynchronous architecture'
[ "$only_floor" = 0 ] || original_cases=
for c in $original_cases; do
 fixture "$c"
 "$D/controller" "$c" "$R/Probe.app" "$R" > "$R/controller.log" 2>&1 & child=$!
 rc=0; wait "$child" || rc=$?; child=
 printf '%s\n' "$rc" > "$R/controller.exit"
 /usr/bin/shasum -a 256 -c "$R/input-sha256.txt" > "$R/input-verification.log"
 echo "$c: exit$rc"; [ "$rc" = 0 ] || status=1
done
/usr/bin/shasum -a 256 -c "$D/input-sha256.txt" > "$D/input-verification.log"
if [ "$only_floor" = 0 ]; then echo 'Original21: fifteen normative cases plus six observations, not21 normative passes.'; fi
for c in i386-selection i386-reuse i386-new-instance worker async-caller-exit; do
 fixture "$c"
 "$D/controller" floor-controls "$c" "$R/Probe.app" "$R" > "$R/controller.log" 2>&1 & child=$!
 rc=0; wait "$child" || rc=$?; child=
 printf '%s\n' "$rc" > "$R/controller.exit"
 /usr/bin/shasum -a 256 -c "$R/input-sha256.txt" > "$R/input-verification.log"
 echo "floor $c: exit$rc"; [ "$rc" = 0 ] || status=1
done
echo 'Floor controls separate from native21; no quiescence or callback-order guarantee.'
exit "$status"
