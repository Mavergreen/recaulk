#!/bin/sh
# platform: macOS-only -- completed JSONL records need schema validation; partial tails stay incomplete
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the pinned shipyard scripts directory}"
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-records.XXXXXX")
trap 'rm -rf "$T"' EXIT
arch=$(uname -m)
case "$arch" in arm64) floor=11.0 ;; x86_64) floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
printf '#define main unused_oracle_main\n#include "%s/tests/c/objc_workspace_reference.m"\n#undef main\n' "$ROOT" > "$T/records.m"
cat >> "$T/records.m" <<'SOURCE'
static void put(NSString *p, NSString *s) {
 if (![s writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL]) [NSException raise:@"TestIO" format:@"write failed"];
}
int main(int argc, char **argv) {
 NSAutoreleasePool *pool = [NSAutoreleasePool new];
 NSString *dir = [NSString stringWithUTF8String:argv[1]];
 pid_t pid = 2147480000; /* synthetic exited-process evidence; never used for cleanup */
 NSString *p = [dir stringByAppendingPathComponent:@"2147480000.jsonl"];
 NSString *startup = @"{\"kind\":\"startup\",\"pid\":2147480000,\"sequence\":0,\"argv\":[\"fixture\"],\"sentinel\":null,\"architecture\":\"arm64\"}\n";
 put(p,[startup stringByAppendingString:@"{\"kind\":"]);
 NSDictionary *s = recordSnapshot(dir,pid);
 BOOL ok = [[s objectForKey:@"records"] count] == 1 && [[s objectForKey:@"incomplete_tail_bytes"] unsignedIntegerValue] > 0;
 put(p,[startup stringByAppendingString:@"{\"kind\":\"finished-launching\",\"pid\":2147480000,\"sequence\":1}\n"]);
 s = recordSnapshot(dir,pid);
 ok &= [[s objectForKey:@"records"] count] == 2 && [[s objectForKey:@"incomplete_tail_bytes"] unsignedIntegerValue] == 0;
 NSArray *bad = @[@"[]\n", @"{\"kind\":\"startup\",\"pid\":2147480000,\"sequence\":0}\n", @"{\"kind\":\"finished-launching\",\"pid\":7,\"sequence\":0}\n", @"{\"kind\":\"finished-launching\",\"pid\":2147480000,\"sequence\":9}\n", @"{\"kind\":\"unknown\",\"pid\":2147480000,\"sequence\":0}\n", @"{\"kind\":\"open\",\"pid\":2147480000,\"sequence\":0,\"urls\":[42],\"direct_string\":\"\",\"event_class\":1,\"event_id\":1}\n"];
 for (NSString *b in bad) {
  put(p,b); BOOL raised = NO;
  @try { recordSnapshot(dir,pid); } @catch (NSException *e) { raised = [e.name isEqual:@"WorkspaceEvidenceError"]; }
  ok &= raised;
 }
 // A schema-valid record must still not be read through a symlink/hardlink.
 NSString *source = [dir stringByAppendingPathComponent:@"unrelated-records"];
 put(source,startup);
 [[NSFileManager defaultManager] removeItemAtPath:p error:NULL];
 ok &= [[NSFileManager defaultManager] createSymbolicLinkAtPath:p withDestinationPath:source error:NULL];
 BOOL linkRaised = NO;
 @try { recordSnapshot(dir,pid); } @catch (NSException *e) { linkRaised = [e.name isEqual:@"WorkspaceEvidenceError"]; }
 ok &= linkRaised;
 [[NSFileManager defaultManager] removeItemAtPath:p error:NULL];
 ok &= link(source.fileSystemRepresentation,p.fileSystemRepresentation) == 0;
 linkRaised = NO;
 @try { recordSnapshot(dir,pid); } @catch (NSException *e) { linkRaised = [e.name isEqual:@"WorkspaceEvidenceError"]; }
 ok &= linkRaised;
 printf("partial-write, exited-record, schema and linked-log checks: %d\n",ok);
 [pool drain]; return ok ? 0 : 1;
}
SOURCE
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$T/records.m" -o "$T/records" -framework AppKit -framework Carbon
"$T/records" "$T"
