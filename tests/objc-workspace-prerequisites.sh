#!/bin/sh
# platform: host-agnostic -- builds the launch oracle with clang22; on 10.9 invalid inputs must fail, not skip as a missing method (RECAULK_TEST_PHASE)
set -eu
umask 077
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macos.sh
ref="$(tbin reference)"
if compiling; then
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations -Werror=objc-method-access \
    tests/c/objc_workspace_reference.m -o "$ref" -framework AppKit -framework Carbon
  check_loads "$ref"
fi
runtime_half
X=$(mktemp -d "${TMPDIR:-/tmp}/workspace-prerequisites.XXXXXX")
trap 'rm -rf "$X"' EXIT
for c in stopped unknown-case; do
  mkdir -p "$X/$c/events"
  rc=0
  "$ref" "$c" "$X/Missing.app" "$X/$c" >"$X/$c/log" 2>&1 || rc=$?
  [ "$rc" = 1 ] || { echo "FAIL: invalid $c prerequisites returned $rc, expected 1 (not a missing-method skip)"; exit 1; }
  plist_util -convert xml1 -o "$X/$c/result.plist" "$X/$c/controller.json"
  disposition=$(plist_buddy -c 'Print :disposition' "$X/$c/result.plist")
  [ "$disposition" = failed ] || { echo "FAIL: invalid $c input not reported as failed"; exit 1; }
  if [ "$c" = unknown-case ]; then
    reason=$(plist_buddy -c 'Print :failures:0' "$X/$c/result.plist")
    [ "$reason" = 'unknown case' ] || { echo "FAIL: unknown case not diagnosed before native execution"; exit 1; }
  fi
done
echo 'oracle prerequisites: invalid fixtures and unknown cases fail, never skip'
