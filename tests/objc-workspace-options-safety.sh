#!/bin/sh
# platform: host-agnostic -- builds the options oracle with clang22; on 10.9 every unsafe input must fail before launch (RECAULK_TEST_PHASE)
set -eu
umask 077
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macos.sh
ref="$(tbin options-reference)"
probe="$(tbin probe)"
if compiling; then
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations tests/c/objc_workspace_options_reference.m -o "$ref" \
    -framework AppKit -framework Carbon
  "$CC" $FLAGS -fno-objc-arc tests/c/objc_workspace_probe_app.m -o "$probe" -framework AppKit -framework Carbon
  check_loads "$ref" "$probe"
fi
runtime_half
D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-options-safety.XXXXXX")
trap 'rm -rf "$D"' EXIT
fixture() {
  R="$D/$1"
  mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
  cp "$probe" "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
  plist_util -convert xml1 -o "$R/Probe.app/Contents/Info.plist" tests/fixtures/workspace-probe-Info.plist.in
  plist_buddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
  plist_buddy -c "Set :CFBundleIdentifier org.mavergreen.workspace-options.$(basename "$D" | tr -cd 'a-zA-Z0-9').$1" "$R/Probe.app/Contents/Info.plist"
  code_sign --force --sign - "$R/Probe.app" > "$R/codesign.log" 2>&1
  shasum -a 256 "$R/Probe.app/Contents/MacOS/WorkspaceProbe" "$R/Probe.app/Contents/Info.plist" > "$R/input-sha256.txt"
}
run_case() {
  rc=0
  "$ref" "$1" "$2" "$R" > "$R/controller.log" 2>&1 || rc=$?
  shasum -a 256 -c "$R/input-sha256.txt" > "$R/input-verification.log"
}
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
