#!/bin/sh
# platform: host-agnostic -- builds the oracle's sentinel matchers with clang22 for 10.9; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: tests/README.objc-workspace.md "Contract and permission boundary" -- a custom event must carry the
#       exact payload; startup must carry the exact sentinel argv and environment
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh

if compiling; then
  S="$(tbin sentinels.m)"
  printf '#define main unused_oracle_main\n#include "%s/tests/c/objc_workspace_reference.m"\n#undef main\n' "$(pwd -P)" > "$S"
  cat >> "$S" <<'SOURCE'
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
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations "$S" -o "$(tbin sentinels)" -framework AppKit -framework Carbon
  check_loads "$(tbin sentinels)"
fi
runtime_half
"$(tbin sentinels)"
