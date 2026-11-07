#!/bin/sh
# platform: host-agnostic -- builds the reference harness's URL matcher for x86_64; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: tests/README.objc-workspace.md -- file URL referents may differ lexically after Launch Services delivery;
#       the real matcher accepts the same file by another path and nothing else
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh

if compiling; then
  D="$(dirname "$(tbin x)")"
  printf '#define main unused_oracle_main\n#include "%s/tests/c/objc_workspace_reference.m"\n#undef main\n' "$(pwd -P)" > "$D/match.m"
  cat >> "$D/match.m" <<'SOURCE'
int main(int argc, char **argv) {
 NSAutoreleasePool *pool = [NSAutoreleasePool new];
 NSString *dir = [NSString stringWithUTF8String:argv[1]];
 NSString *target = [dir stringByAppendingPathComponent:@"file"];
 NSString *link = [dir stringByAppendingPathComponent:@"alias"];
 if (![@"sentinel" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:NULL] ||
     ![[NSFileManager defaultManager] createSymbolicLinkAtPath:link withDestinationPath:target error:NULL]) return 1;
 NSArray *rs = @[@{@"kind": @"open", @"urls": @[[[NSURL fileURLWithPath:target] absoluteString], @"https://workspace-probe.invalid/exact"]}];
 BOOL equivalent = contains(rs, @"open", [[NSURL fileURLWithPath:link] absoluteString]);
 BOOL wrongFile = contains(rs, @"open", [[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"other"]] absoluteString]);
 BOOL exact = contains(rs, @"open", @"https://workspace-probe.invalid/exact");
 BOOL wrongNonfile = contains(rs, @"open", @"https://workspace-probe.invalid/exact/");
 BOOL wrongKind = contains(rs, @"print", [[NSURL fileURLWithPath:link] absoluteString]);
 printf("equivalent-file=%d wrong-file=%d exact-https=%d changed-https=%d wrong-kind=%d\n", equivalent, wrongFile, exact, wrongNonfile, wrongKind);
 [pool drain];
 return equivalent && !wrongFile && exact && !wrongNonfile && !wrongKind ? 0 : 1;
}
SOURCE
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations "$D/match.m" -o "$(tbin match)" -framework AppKit -framework Carbon
  check_loads "$(tbin match)"
fi
runtime_half
S="$(mktemp -d "${TMPDIR:-/tmp}/workspace-file-url.XXXXXX")"
trap 'rm -rf "$S"' EXIT
"$(tbin match)" "$S"
