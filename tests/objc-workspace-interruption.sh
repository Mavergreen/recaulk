#!/bin/sh
# platform: macOS-only -- interrupt only owned controller/shell children; require fixture cleanup
set -eu
umask 077
# This regression intentionally exercises the legacy shell/controller boundary.
unset RECAULK_WORKSPACE_CONTEXT
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the pinned shipyard scripts directory}"
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-interruption.XXXXXX")
T=$(cd "$T" && pwd -P)
child=''; current=''
finish() {
 if [ -n "$child" ]; then kill -TERM "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; fi
 if [ -x "$T/cleanup" ] && [ -n "$current" ]; then "$T/cleanup" "$current" || :; fi
 rm -rf "$T"
}
trap finish EXIT
arch=$(uname -m)
case "$arch" in arm64) floor=11.0 ;; x86_64) floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$ROOT/tests/c/objc_workspace_reference.m" -o "$T/reference" -framework AppKit -framework Carbon
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc "$ROOT/tests/c/objc_workspace_probe_app.m" -o "$T/probe" -framework AppKit -framework Carbon
printf '#define main unused_oracle_main\n#include "%s/tests/c/objc_workspace_reference.m"\n#undef main\n' "$ROOT" > "$T/cleanup.m"
cat >> "$T/cleanup.m" <<'SOURCE'
int main(int argc, char **argv) {
 NSAutoreleasePool *pool = [NSAutoreleasePool new];
 NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
 BOOL found = NO;
 for (NSRunningApplication *a in [NSWorkspace sharedWorkspace].runningApplications) if (owned(a,url)) {
  found = YES; [a terminate];
  NSTimeInterval end = [NSProcessInfo processInfo].systemUptime+2;
  while (!a.terminated && [NSProcessInfo processInfo].systemUptime < end) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  if (!a.terminated && owned(a,url)) [a forceTerminate];
 }
 [pool drain]; return found ? 1 : 0;
}
SOURCE
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$T/cleanup.m" -o "$T/cleanup" -framework AppKit -framework Carbon
for mode in controller shell; do
 for sig in INT TERM HUP; do
  R="$T/$mode-$sig"
  if [ "$mode" = controller ]; then
   mkdir -p "$R/Probe.app/Contents/MacOS" "$R/events"
   cp "$T/probe" "$R/Probe.app/Contents/MacOS/WorkspaceProbe"
   cp "$ROOT/tests/fixtures/workspace-probe-Info.plist.in" "$R/Probe.app/Contents/Info.plist"
   /usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $R/events" "$R/Probe.app/Contents/Info.plist"
   /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.interruption.$$.${sig}" "$R/Probe.app/Contents/Info.plist"
   /usr/bin/codesign --force --sign - "$R/Probe.app" > "$T/sign.log" 2>&1
   "$T/reference" stopped "$R/Probe.app" "$R" > "$T/run.log" 2>&1 & child=$!
   caseDir=$R; expected=1
  else
   # A background job inherits ignored SIGINT from a POSIX shell. Restore the
   # terminal's ordinary dispositions before exec, as the repository runner does.
   /usr/bin/perl -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec @ARGV or die $!' sh "$ROOT/tests/objc-workspace-reference.sh" --report "$R" > "$T/run.log" 2>&1 & child=$!
   caseDir="$R/stopped"; expected=130
  fi
  current="$caseDir/Probe.app"
  count=0
  while :; do
   ready=0
   for log in "$caseDir"/events/*.jsonl; do [ ! -f "$log" ] || ready=1; done
   [ "$ready" = 0 ] || break
   if ! kill -0 "$child" 2>/dev/null || [ "$count" -ge 300 ]; then
    rc=0; wait "$child" || rc=$?; child=''
    [ "$rc" != 77 ] || exit 77
    echo "FAIL: $mode $sig fixture readiness, exit=$rc"; exit 1
   fi
   sleep 0.05; count=$((count+1))
  done
  kill -"$sig" "$child"
  rc=0; wait "$child" || rc=$?; child=''
  [ "$rc" = "$expected" ] || { echo "FAIL: $mode $sig exit=$rc expected=$expected"; exit 1; }
  grep -Eq '"cleanup_completed"[[:space:]]*:[[:space:]]*true' "$caseDir/controller.json" || exit 1
  grep -q '"interrupted_signal"' "$caseDir/controller.json" || exit 1
  "$T/cleanup" "$current" || { echo "FAIL: $mode $sig left fixture running"; exit 1; }
  current=''
  echo "$mode $sig: interrupted report and verified cleanup"
 done
done
