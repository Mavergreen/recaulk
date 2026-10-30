#!/bin/sh
# platform: macOS-only -- invalid oracle inputs must fail even when the system method is absent
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the pinned shipyard scripts directory}"
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-prerequisites.XXXXXX")
trap 'rm -rf "$T"' EXIT
arch=$(uname -m)
case "$arch" in arm64) floor=11.0 ;; x86_64) floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" \
  -fno-objc-arc -Wno-deprecated-declarations -Werror=objc-method-access "$ROOT/tests/c/objc_workspace_reference.m" \
  -o "$T/reference" -framework AppKit -framework Carbon
for c in stopped unknown-case; do
  mkdir -p "$T/$c/events"
  rc=0
  "$T/reference" "$c" "$T/Missing.app" "$T/$c" >"$T/$c/log" 2>&1 || rc=$?
  [ "$rc" = 1 ] || { echo "FAIL: invalid $c prerequisites returned $rc, expected 1 (not a missing-method skip)"; exit 1; }
  /usr/bin/plutil -convert xml1 -o "$T/$c/result.plist" "$T/$c/controller.json"
  disposition=$(/usr/libexec/PlistBuddy -c 'Print :disposition' "$T/$c/result.plist")
  [ "$disposition" = failed ] || { echo "FAIL: invalid $c input not reported as failed"; exit 1; }
  if [ "$c" = unknown-case ]; then
    reason=$(/usr/libexec/PlistBuddy -c 'Print :failures:0' "$T/$c/result.plist")
    [ "$reason" = 'unknown case' ] || { echo "FAIL: unknown case not diagnosed before native execution"; exit 1; }
  fi
done
echo 'oracle prerequisites: invalid fixtures and unknown cases fail, never skip'
