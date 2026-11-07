#!/bin/sh
# platform: macOS-only -- drives REAL Launch Services delivery on 10.9, which needs a logged-in GUI (Aqua) session;
#           the 10.9 guest runs its tests over ssh, with none, so this runs on a Mavericks box's desktop
# spec: tests/README.objc-workspace.md "Actual-method delivery and immutable reference routing" -- private fixture
#       apps only, no Automation requests; with no arguments only the floor controls run
#   usage: objc-workspace-backfill.sh [--report NEW_ABSOLUTE_DIR [--floor-controls-only]]
set -eu
umask 077
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
usage() { echo 'usage: objc-workspace-backfill.sh [--report NEW_ABSOLUTE_DIR [--floor-controls-only]]' >&2; exit 2; }
only_floor=1; RPT=
case "$#" in
  0) ;;
  2|3) [ "$1" = --report ] || usage
       RPT=$2; only_floor=0
       if [ "$#" = 3 ]; then [ "$3" = --floor-controls-only ] || usage; only_floor=1; fi
       case "$RPT" in /*) ;; *) usage ;; esac ;;
  *) usage ;;
esac
. tests/helpers/built.sh
. tests/helpers/macos.sh
P="$T"
A="$P/lib/librecaulk-objc.a"

if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  [ -f tests/c/objc_workspace_backfill_integration.m ] || { echo 'FAIL: actual-method integration driver absent'; exit 1; }
  E="$(dirname "$(tbin x)")"
  "$CC" --version > "$E/compiler.txt"
  shasum -a 256 "$A" | cut -d' ' -f1 > "$E/linked-archive.sha256"
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations tests/c/objc_workspace_backfill_integration.m \
    -o "$(tbin controller)" "$A" -Wl,-u,___recaulk_objc_activate -framework AppKit -framework Carbon
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations tests/c/objc_workspace_backfill_integration.m \
    -o "$(tbin negative-controller)" -framework AppKit -framework Carbon
  # platform: lld cannot link i386, so the probe is x86_64 only and the i386 floor controls are not measured
  "$CC" $FLAGS -fno-objc-arc tests/c/objc_workspace_probe_app.m -o "$(tbin probe)" -framework AppKit -framework Carbon
  check_loads "$(tbin controller)" "$(tbin negative-controller)" "$(tbin probe)"
fi
runtime_half
[ "$(launchctl managername)" = Aqua ] || { echo "SKIP: no GUI session here, and Launch Services launches apps only in one"; exit 77; }
case "$(macos_version)" in
  10.9.*) ;;
  *) [ -z "$RPT" ] || { echo 'FAIL: actual Mavericks required'; exit 1; }
     echo 'SKIP: real backfill delivery runs only on Mavericks; not measured'; exit 77 ;;
esac
[ -z "${DYLD_INSERT_LIBRARIES:-}${DYLD_FRAMEWORK_PATH:-}${DYLD_LIBRARY_PATH:-}" ] || exit 1
E="$(dirname "$(tbin x)")"
if [ -z "$RPT" ]; then
  # platform: /var and /tmp are symlinks to /private; report paths must have none
  S=$(mktemp -d "${TMPDIR:-/tmp}/workspace-backfill.XXXXXX")
  S=$(cd "$S" && pwd -P)
  RPT="$S/report"
  echo "evidence: $RPT"
fi
cursor=$RPT
while [ "$cursor" != / ]; do [ ! -L "$cursor" ] || { echo 'FAIL: symlink report component'; exit 1; }; cursor=$(dirname "$cursor"); done
mkdir -m 700 "$RPT"
# spec: tests/README.objc-workspace.md "Actual-method delivery and immutable reference routing" -- a stale prefix fails:
#       its manifest's source receipt must match this tree and its archive hash the archive the controller linked
plist_util -convert xml1 -o "$RPT/objc-providers.plist" "$P/share/recaulk/objc-providers.json"
plist_buddy -c 'Print :build:source_inputs_receipt' "$RPT/objc-providers.plist" | grep -v '  generated/' | grep . > "$RPT/source-inputs-receipt.txt"
[ "$(plist_buddy -c 'Print :build:architecture' "$RPT/objc-providers.plist")" = x86_64 ] || { echo 'FAIL: prefix archive is not x86_64'; exit 1; }
(cd "$ROOT" && /usr/bin/shasum -a 256 -c "$RPT/source-inputs-receipt.txt") > "$RPT/source-inputs-verification.log" 2>&1 || { echo 'FAIL: prefix archive was not built from this tree'; cat "$RPT/source-inputs-verification.log"; exit 1; }
archive_sha=$(/usr/bin/shasum -a 256 "$A" | cut -d' ' -f1)
[ "$archive_sha" = "$(plist_buddy -c 'Print :build:archive_sha256' "$RPT/objc-providers.plist")" ] || { echo 'FAIL: prefix archive does not match its manifest'; exit 1; }
[ "$archive_sha" = "$(cat "$E/linked-archive.sha256")" ] || { echo 'FAIL: the controller was linked to a different librecaulk-objc.a than the prefix holds'; exit 1; }
cp "$E/compiler.txt" "$RPT/compiler.txt"
/usr/bin/shasum -a 256 "$A" "$ROOT/tests/c/objc_workspace_reference.m" "$ROOT/tests/c/objc_workspace_options_reference.m" "$ROOT/tests/c/objc_workspace_probe_app.m" "$ROOT/tests/fixtures/workspace-probe-Info.plist.in" "$ROOT/tests/c/objc_workspace_backfill_integration.m" "$(tbin controller)" "$(tbin negative-controller)" "$(tbin probe)" > "$RPT/input-sha256.txt"
fixture() {
  R=$RPT/$1
  mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
  cp "$(tbin probe)" "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
  plist_util -convert xml1 -o "$R/Probe.app/Contents/Info.plist" "$ROOT/tests/fixtures/workspace-probe-Info.plist.in"
  plist_buddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
  plist_buddy -c "Set :CFBundleIdentifier org.mavergreen.workspace.backfill.$(basename "$(dirname "$RPT")" | tr -cd 'a-zA-Z0-9').$(basename "$RPT" | tr -cd 'a-zA-Z0-9').$1" "$R/Probe.app/Contents/Info.plist"
  code_sign --force --sign - "$R/Probe.app" > "$R/signing.log" 2>&1
  /usr/bin/shasum -a 256 "$R/Probe.app/Contents/MacOS/WorkspaceProbe" "$R/Probe.app/Contents/Info.plist" > "$R/input-sha256.txt"
}
fixture negative-activation
rc=0; "$(tbin negative-controller)" stopped "$R/Probe.app" "$R" > "$R/controller.log" 2>&1 || rc=$?
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
  "$(tbin controller)" "$c" "$R/Probe.app" "$R" > "$R/controller.log" 2>&1 & child=$!
  rc=0; wait "$child" || rc=$?; child=
  printf '%s\n' "$rc" > "$R/controller.exit"
  /usr/bin/shasum -a 256 -c "$R/input-sha256.txt" > "$R/input-verification.log"
  echo "$c: exit$rc"; [ "$rc" = 0 ] || status=1
done
/usr/bin/shasum -a 256 -c "$RPT/input-sha256.txt" > "$RPT/input-verification.log"
if [ "$only_floor" = 0 ]; then echo 'Original21: fifteen normative cases plus six observations, not21 normative passes.'; fi
for c in i386-selection i386-new-instance; do echo "floor $c: not measured (no i386 probe slice)"; done
for c in i386-reuse worker async-caller-exit ls-mixed; do
  fixture "$c"
  "$(tbin controller)" floor-controls "$c" "$R/Probe.app" "$R" > "$R/controller.log" 2>&1 & child=$!
  rc=0; wait "$child" || rc=$?; child=
  printf '%s\n' "$rc" > "$R/controller.exit"
  /usr/bin/shasum -a 256 -c "$R/input-sha256.txt" > "$R/input-verification.log"
  echo "floor $c: exit$rc"
  if [ "$rc" != 0 ]; then status=1; sed "s/^/  $c: /" "$R/controller.log" | tail -15; fi
done
echo 'Floor controls separate from native21; no quiescence or callback-order guarantee.'
exit "$status"
