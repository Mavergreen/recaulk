/* Same-TU access to the REAL private default lookup, no runtime swizzle/hook.
 * Missing deadline would hang: self-only alarm turns that mutation into failure.
 * This is a characterization of the bounded unavailable path, not original RED. */
#include "../../src/objc/workspace.m"
#include <unistd.h>
#include <limits.h>
#include <stdio.h>
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new]; alarm(3);
    NSTimeInterval start=[[NSProcessInfo processInfo] systemUptime];
    NSRunningApplication *app=lookup(INT_MAX);
    NSTimeInterval elapsed=[[NSProcessInfo processInfo] systemUptime]-start;
    alarm(0);
    BOOL ok=!app || !app.bundleURL || app.executableArchitecture<=0;
    /* The budget is 250ms: polling must really happen (>=0.2s) and stop near
     * the budget (<=0.6s), so a removed or widened deadline fails here. */
    BOOL bounded=elapsed>=0.2 && elapsed<=0.6;
    printf("%s: actual public unavailable-identity lookup returns without a caller loop; no provisional usable identity\n",ok ? "PASS":"FAIL");
    printf("%s: unavailable lookup polled for %.3fs, within the 0.25s budget's bounds\n",bounded ? "PASS":"FAIL",elapsed);
    ok=ok && bounded;
    [pool drain]; return ok ? 0:1;
}
