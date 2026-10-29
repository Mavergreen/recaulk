#!/bin/sh
# platform: macOS-only -- startup sentinels require exact argument sequence and environment
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the pinned shipyard scripts directory}"
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-sentinels.XXXXXX")
trap 'rm -rf "$T"' EXIT
arch=$(uname -m)
case "$arch" in arm64) floor=11.0 ;; x86_64) floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
printf '#define main unused_oracle_main\n#include "%s/tests/c/objc_workspace_reference.m"\n#undef main\n' "$ROOT" > "$T/sentinels.m"
cat >> "$T/sentinels.m" <<'SOURCE'
int main(void) {
 NSAutoreleasePool *pool = [NSAutoreleasePool new];
 NSArray *wanted = @[@"--workspace-sentinel", @"argv exact value"];
 NSDictionary *valid = @{@"argv": @[@"/fixture", @"--workspace-sentinel", @"argv exact value"], @"sentinel": @"environment exact value"};
 NSMutableDictionary *bad = [NSMutableDictionary dictionaryWithDictionary:valid];
 BOOL ok = startupMatches(valid,wanted,@"environment exact value");
 [bad setObject:@[@"/fixture", @"argv exact value", @"--workspace-sentinel"] forKey:@"argv"];
 ok &= !startupMatches(bad,wanted,@"environment exact value");
 [bad setObject:@[@"/fixture", @"--workspace-sentinel", @"argv exact value", @"--injected"] forKey:@"argv"];
 ok &= !startupMatches(bad,wanted,@"environment exact value");
 [bad setObject:valid[@"argv"] forKey:@"argv"]; [bad setObject:@"replaced" forKey:@"sentinel"];
 ok &= !startupMatches(bad,wanted,@"environment exact value");
 ok &= customPayload(@[@{@"kind":@"custom",@"direct_string":@"custom sentinel"}],@"custom sentinel");
 ok &= !customPayload(@[@{@"kind":@"custom",@"direct_string":@"wrong"}],@"custom sentinel");
 printf("exact sentinels and payload: %d\n",ok); [pool drain]; return ok ? 0 : 1;
}
SOURCE
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations "$T/sentinels.m" -o "$T/sentinels" -framework AppKit -framework Carbon
"$T/sentinels"
