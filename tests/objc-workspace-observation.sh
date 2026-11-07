#!/bin/sh
# platform: host-agnostic -- builds the oracle's record observer with clang22 for 10.9; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: tests/README.objc-workspace.md "Contract and permission boundary" -- bounded observation
#       deadlines and partial JSONL states are not quiescence proofs, so an actual child's exit and
#       concurrent writes must retain bounded incomplete evidence
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh

if compiling; then
  S="$(tbin observation.m)"
  printf '#define main unused_oracle_main\n#include "%s/tests/c/objc_workspace_reference.m"\n#undef main\n' "$(pwd -P)" > "$S"
  cat >> "$S" <<'SOURCE'
#include <fcntl.h>
#include <limits.h>
#include <string.h>
static BOOL putBytes(int fd, const char *bytes, size_t length) {
 while (length) { ssize_t n = write(fd,bytes,length); if (n <= 0) return NO; bytes += n; length -= n; }
 return YES;
}
static int writer(const char *dir) {
 char path[PATH_MAX], json[1024]; pid_t pid = getpid();
 snprintf(path,sizeof(path),"%s/%d.jsonl",dir,pid);
 int fd = open(path,O_WRONLY|O_CREAT|O_EXCL,0600); if (fd < 0) return 2;
 snprintf(json,sizeof(json),"{\"kind\":\"startup\",\"pid\":%d,\"sequence\":0,\"argv\":[\"fixture\"],\"sentinel\":\"writer\",\"architecture\":\"%s\"}\n",pid,[hostArch() UTF8String]);
 if (!putBytes(fd,json,strlen(json))) return 2;
 snprintf(json,sizeof(json),"{\"kind\":\"finished-launching\",\"pid\":%d,\"sequence\":1,\"note\":\"",pid);
 if (!putBytes(fd,json,strlen(json)) || !putBytes(fd,"\xe2",1)) return 2;
 snprintf(path,sizeof(path),"%s/ready",dir);
 int ready = open(path,O_WRONLY|O_CREAT|O_EXCL,0600); if (ready < 0) return 2; close(ready);
 snprintf(path,sizeof(path),"%s/finish",dir);
 int count = 0; while (access(path,F_OK) && ++count < 10000) usleep(1000);
 if (count >= 10000) return 3;
 BOOL ok = putBytes(fd,"\x98\x83\"}\n",5); close(fd); return ok ? 0 : 2;
}
int main(int argc, char **argv) {
 NSAutoreleasePool *pool = [NSAutoreleasePool new];
 if (argc == 3 && !strcmp(argv[1],"--writer")) return writer(argv[2]);
 if (argc != 2) return 2;
 NSString *dir = [NSString stringWithUTF8String:argv[1]];
 NSTask *task = [NSTask new];
 task.launchPath = [NSString stringWithUTF8String:argv[0]];
 task.arguments = @[@"--writer",dir]; [task launch];
 NSTimeInterval start = [[NSProcessInfo processInfo] systemUptime];
 while (![[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"ready"]] && [[NSProcessInfo processInfo] systemUptime]-start < 5 && [task isRunning])
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
 BOOL ready = [[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"ready"]];
 if (!ready) { [task terminate]; [task waitUntilExit]; fprintf(stderr,"FAIL: writer readiness\n"); return 1; }
 start = [[NSProcessInfo processInfo] systemUptime];
 NSDictionary *pending = waitRecordSnapshot(dir,task.processIdentifier,@[],@"finished-launching",0.15);
 NSTimeInterval elapsed = [[NSProcessInfo processInfo] systemUptime]-start;
 BOOL ok = ![[pending objectForKey:@"requirements_observed"] boolValue] && [[pending objectForKey:@"deadline_expired"] boolValue] &&
  [[pending objectForKey:@"incomplete_tail_bytes"] unsignedIntegerValue] > 0 && [[pending objectForKey:@"records"] count] == 1 &&
  [task isRunning] && elapsed >= 0.10 && elapsed < 3;
 ok &= [@"finish" writeToFile:[dir stringByAppendingPathComponent:@"finish"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 [task waitUntilExit];
 NSDictionary *complete = waitRecordSnapshot(dir,task.processIdentifier,@[],@"finished-launching",0.15);
 ok &= ![task isRunning] && task.terminationStatus == 0 && [[complete objectForKey:@"requirements_observed"] boolValue] &&
  ![[complete objectForKey:@"deadline_expired"] boolValue] && [[complete objectForKey:@"incomplete_tail_bytes"] unsignedIntegerValue] == 0 &&
  [[complete objectForKey:@"records"] count] == 2;
 NSDictionary *missing = waitRecordSnapshot(dir,2147480000,@[],nil,0.03);
 ok &= [[missing objectForKey:@"file_missing"] boolValue] && [[missing objectForKey:@"deadline_expired"] boolValue] &&
  ![[missing objectForKey:@"requirements_observed"] boolValue];
 printf("live partial UTF-8/deadline, completed exited child, missing file: %d\n",ok);
 [task release]; [pool drain]; return ok ? 0 : 1;
}
SOURCE
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations "$S" -o "$(tbin observation)" -framework AppKit -framework Carbon
  check_loads "$(tbin observation)"
fi
runtime_half
R="$(mktemp -d "${TMPDIR:-/tmp}/workspace-observation.XXXXXX")"
trap 'rm -rf "$R"' EXIT
"$(tbin observation)" "$R"
