#!/bin/sh
# platform: macOS-only -- launches a malformed fixture app through the native openURLs: method, which stock 10.9 lacks; its evidence must fail, never pass as an observation
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
. build/lib.sh
recaulk_tools
X=$(mktemp -d "${TMPDIR:-/tmp}/workspace-harness-errors.XXXXXX")
trap 'rm -rf "$X"' EXIT
. "$ROOT/tests/helpers/native-arch.sh"
"$CC" $OFLAGS -Wno-deprecated-declarations tests/c/objc_workspace_reference.m -o "$X/reference" \
  -framework AppKit -framework Carbon
mkdir -p "$X/Probe.app/Contents/MacOS" "$X/events"
cat > "$X/bad.m" <<'SOURCE'
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
"$CC" $OFLAGS -fno-objc-arc "$X/bad.m" -o "$X/Probe.app/Contents/MacOS/WorkspaceProbe" -framework AppKit
cp "$ROOT/tests/fixtures/workspace-probe-Info.plist.in" "$X/Probe.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $X/events" "$X/Probe.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.malformed.$$.probe" "$X/Probe.app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$X/Probe.app" > "$X/sign.log" 2>&1
rc=0
"$X/reference" asynchronous "$X/Probe.app" "$X" > "$X/run.log" 2>&1 || rc=$?
[ "$rc" != 77 ] || { echo 'SKIP: this macOS has no native openURLs:withApplicationAtURL:options:configuration:error:'; exit 77; }
[ "$rc" = 1 ] || { echo "FAIL: malformed evidence classified as native observation, exit=$rc"; exit 1; }
# platform: an XML plist cannot represent the report's JSON null error fields, so the disposition is read as text
grep -Eq '"disposition"[[:space:]]*:[[:space:]]*"failed"' "$X/controller.json" || { echo 'FAIL: malformed evidence not reported as failed'; exit 1; }
echo 'malformed harness evidence fails even in observation-only cases'
