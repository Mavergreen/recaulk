#!/bin/sh
# platform: macOS-only -- file URL referents may differ lexically after Launch Services delivery
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the pinned shipyard scripts directory}"
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-file-url.XXXXXX")
trap 'rm -rf "$T"' EXIT
arch=$(uname -m)
case "$arch" in arm64) floor=11.0 ;; x86_64) floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
# Include the real matcher. No replacement system API, fixture launch or Recaulk.
printf '#define main unused_oracle_main\n#include "%s/tests/c/objc_workspace_reference.m"\n#undef main\n' "$ROOT" > "$T/match.m"
cat >> "$T/match.m" <<'SOURCE'
int main(int argc, char **argv) {
 NSAutoreleasePool *pool = [NSAutoreleasePool new];
 NSString *dir = [NSString stringWithUTF8String:argv[1]];
 NSString *target = [dir stringByAppendingPathComponent:@"file"];
 NSString *link = [dir stringByAppendingPathComponent:@"alias"];
 if (![@"sentinel" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:NULL] ||
     ![[NSFileManager defaultManager] createSymbolicLinkAtPath:link withDestinationPath:target error:NULL]) return 1;
 NSArray *rs = @[@{@"kind": @"open", @"urls": @[[NSURL fileURLWithPath:target].absoluteString, @"https://workspace-probe.invalid/exact"]}];
 BOOL equivalent = contains(rs, @"open", [NSURL fileURLWithPath:link].absoluteString);
 BOOL wrongFile = contains(rs, @"open", [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"other"]].absoluteString);
 BOOL exact = contains(rs, @"open", @"https://workspace-probe.invalid/exact");
 BOOL wrongNonfile = contains(rs, @"open", @"https://workspace-probe.invalid/exact/");
 BOOL wrongKind = contains(rs, @"print", [NSURL fileURLWithPath:link].absoluteString);
 printf("equivalent-file=%d wrong-file=%d exact-https=%d changed-https=%d wrong-kind=%d\n", equivalent, wrongFile, exact, wrongNonfile, wrongKind);
 [pool drain];
 return equivalent && !wrongFile && exact && !wrongNonfile && !wrongKind ? 0 : 1;
}
SOURCE
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$T/match.m" -o "$T/match" -framework AppKit -framework Carbon
"$T/match" "$T"
