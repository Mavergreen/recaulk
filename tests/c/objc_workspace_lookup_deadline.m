/* Same-TU access to the REAL private default lookup, no runtime swizzle/hook.
 * Missing deadline would hang: self-only alarm turns that mutation into failure.
 * This is a characterization of the bounded unavailable path, not original RED. */
#include "../../src/objc/workspace.m"
#include <unistd.h>
#include <limits.h>
#include <stdio.h>
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new]; alarm(3);
    NSRunningApplication *app=lookup(INT_MAX);
    alarm(0);
    BOOL ok=!app || !app.bundleURL || app.executableArchitecture<=0;
    printf("%s: actual public unavailable-identity lookup returns without a caller loop; no provisional usable identity\n",ok ? "PASS":"FAIL");
    [pool drain]; return ok ? 0:1;
}
