/* Regression: a print observation cannot finish after only the first batch.
 * Real child writes first batch, then waits for the parent's next run-loop turn.
 * Returning early cannot accidentally pass because the child was scheduled fast. */
#define WORKSPACE_OPTIONS_NO_MAIN 1
#include "objc_workspace_options_reference.m"

static NSString *finishPath;
@interface OptionsWriterRelease : NSObject
- (void)finish:(NSTimer *)timer;
@end
@implementation OptionsWriterRelease
- (void)finish:(NSTimer *)timer { (void)timer; optionsFile(finishPath); }
@end
static int writer(NSString *dir) {
    pid_t pid = getpid();
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.jsonl", pid]];
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) return 2;
    NSString *first = [NSString stringWithFormat:
        @"{\"kind\":\"startup\",\"pid\":%d,\"sequence\":0,\"argv\":[\"fixture\"],\"sentinel\":null,\"architecture\":\"%@\"}\n"
         "{\"kind\":\"print\",\"pid\":%d,\"sequence\":1,\"urls\":[\"file:///private/tmp/options-one.txt\"],\"direct_string\":\"\",\"event_class\":%u,\"event_id\":%u}\n",
         pid, hostArch(), pid, (unsigned)kCoreEventClass, (unsigned)kAEPrintDocuments];
    if (!optionsWrite(fd, [first dataUsingEncoding:NSUTF8StringEncoding]) || !optionsFile([dir stringByAppendingPathComponent:@"ready"])) { close(fd); return 2; }
    NSString *finish = [dir stringByAppendingPathComponent:@"finish"];
    NSTimeInterval deadline = [[NSProcessInfo processInfo] systemUptime] + 8;
    while (access(finish.fileSystemRepresentation, F_OK) && [[NSProcessInfo processInfo] systemUptime] < deadline) usleep(1000);
    if (access(finish.fileSystemRepresentation, F_OK)) { close(fd); return 3; }
    NSString *second = [NSString stringWithFormat:
        @"{\"kind\":\"print\",\"pid\":%d,\"sequence\":2,\"urls\":[\"file:///private/tmp/options-two.txt\"],\"direct_string\":\"\",\"event_class\":%u,\"event_id\":%u}\n",
        pid, (unsigned)kCoreEventClass, (unsigned)kAEPrintDocuments];
    BOOL ok = optionsWrite(fd, [second dataUsingEncoding:NSUTF8StringEncoding]);
    if (close(fd)) ok = NO;
    return ok ? 0 : 2;
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if (argc == 3 && !strcmp(argv[1], "--writer")) return writer([NSString stringWithUTF8String:argv[2]]);
    if (argc != 2) return 2;
    NSString *dir = [NSString stringWithUTF8String:argv[1]];
    NSTask *task = [NSTask new];
    task.launchPath = [NSString stringWithUTF8String:argv[0]];
    task.arguments = @[@"--writer", dir];
    [task launch];
    NSString *ready = [dir stringByAppendingPathComponent:@"ready"];
    NSTimeInterval deadline = [[NSProcessInfo processInfo] systemUptime] + 3;
    while (access(ready.fileSystemRepresentation, F_OK) && [task isRunning] && [[NSProcessInfo processInfo] systemUptime] < deadline)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    if (access(ready.fileSystemRepresentation, F_OK)) { [task terminate]; [task waitUntilExit]; fprintf(stderr, "FAIL: writer readiness\n"); return 1; }
    finishPath = [dir stringByAppendingPathComponent:@"finish"];
    OptionsWriterRelease *releaseWriter = [OptionsWriterRelease new];
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0 target:releaseWriter selector:@selector(finish:) userInfo:nil repeats:NO];
    NSDictionary *snapshot = optionsSnapshot(dir, task.processIdentifier, @[
        [NSURL URLWithString:@"file:///private/tmp/options-one.txt"],
        [NSURL URLWithString:@"file:///private/tmp/options-two.txt"]], YES, NO);
    [timer invalidate];
    /* Release even an erroneously early-returning observer's child. Check the
     * returned immutable snapshot, not a second read after the writer exits. */
    if (access(finishPath.fileSystemRepresentation, F_OK)) optionsFile(finishPath);
    [task waitUntilExit];
    BOOL ok = task.terminationStatus == 0 && [[snapshot objectForKey:@"requirements_observed"] boolValue] &&
        ![[snapshot objectForKey:@"deadline_expired"] boolValue] && [[snapshot objectForKey:@"records"] count] == 3 &&
        contains([snapshot objectForKey:@"records"], @"print", @"file:///private/tmp/options-two.txt");
    printf("%s: print observation waits for every expected file at the returned PID\n", ok ? "PASS" : "FAIL");
    [releaseWriter release]; [task release]; [pool drain];
    return ok ? 0 : 1;
}
