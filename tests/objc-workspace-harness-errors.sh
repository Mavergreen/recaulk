#!/bin/sh
# platform: macOS-only -- malformed fixture evidence must fail, never become a native observation
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the pinned shipyard scripts directory}"
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-harness-errors.XXXXXX")
trap 'rm -rf "$T"' EXIT
arch=$(uname -m)
case "$arch" in arm64) floor=11.0 ;; x86_64) floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$ROOT/tests/c/objc_workspace_reference.m" -o "$T/reference" -framework AppKit -framework Carbon
mkdir -p "$T/Probe.app/Contents/MacOS" "$T/events"
cat > "$T/bad.m" <<'SOURCE'
#import <AppKit/AppKit.h>
#include <unistd.h>
int main(void) {
 NSAutoreleasePool *pool = [NSAutoreleasePool new];
 NSString *dir = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"WorkspaceProbeReportDirectory"];
 NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.jsonl",getpid()]];
 [@"[]\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 [[NSApplication sharedApplication] run]; [pool drain]; return 0;
}
SOURCE
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc "$T/bad.m" -o "$T/Probe.app/Contents/MacOS/WorkspaceProbe" -framework AppKit
cp "$ROOT/tests/fixtures/workspace-probe-Info.plist.in" "$T/Probe.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $T/events" "$T/Probe.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.malformed.$$.probe" "$T/Probe.app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$T/Probe.app" > "$T/sign.log" 2>&1
rc=0
"$T/reference" asynchronous "$T/Probe.app" "$T" > "$T/run.log" 2>&1 || rc=$?
[ "$rc" != 77 ] || exit 77
[ "$rc" = 1 ] || { echo "FAIL: malformed evidence classified as native observation, exit=$rc"; exit 1; }
# JSON null error fields cannot be represented by an XML plist.
grep -Eq '"disposition"[[:space:]]*:[[:space:]]*"failed"' "$T/controller.json" || exit 1
echo 'malformed harness evidence fails even in observation-only cases'
