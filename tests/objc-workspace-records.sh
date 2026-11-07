#!/bin/sh
# platform: host-agnostic -- builds the launch oracle's record reader with clang22; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: tests/c/objc_workspace_reference.m recordSnapshot -- completed JSONL records need schema validation;
#       a partial tail stays incomplete; a linked log is refused
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
prog="$(tbin records)"
if compiling; then
  src="$(dirname "$prog")/records.m"
  printf '#define main unused_oracle_main\n#include "%s/tests/c/objc_workspace_reference.m"\n#undef main\n' "$(pwd -P)" > "$src"
  cat >> "$src" <<'SOURCE'
static void put(NSString *p, NSString *s) {
 if (![s writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL]) [NSException raise:@"TestIO" format:@"write failed"];
}
int main(int argc, char **argv) {
 NSAutoreleasePool *pool = [NSAutoreleasePool new];
 NSString *dir = [NSString stringWithUTF8String:argv[1]];
 pid_t pid = 2147480000;
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
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations "$src" -o "$prog" -framework AppKit -framework Carbon
  check_loads "$prog"
fi
runtime_half
X=$(mktemp -d "${TMPDIR:-/tmp}/workspace-records.XXXXXX")
trap 'rm -rf "$X"' EXIT
"$prog" "$X"
