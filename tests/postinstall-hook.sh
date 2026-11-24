#!/bin/sh
# platform: host-agnostic
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/postinstall-hook.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
V="$t/vol"
ICON="$V/Library/Application Support/Mavergreen/recaulk-updater.app/Contents/Resources/recaulk-updater.icns"
CT="$V/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"
mkdir -p "$(dirname "$ICON")" "$CT"
printf 'placeholder\n' > "$ICON"
printf 'framework\n' > "$CT/GenericFrameworkIcon.icns"
printf 'library\n' > "$CT/LibraryFolderIcon.icns"
ROOT="$V" sh "$R/packaging/postinstall-hook.sh" || fail "the hook must succeed"
[ "$(cat "$ICON")" = framework ] || fail "the updater borrows the TARGET volume's framework icon, first candidate first"
rm -f "$CT"/*.icns; printf 'placeholder\n' > "$ICON"
ROOT="$V" sh "$R/packaging/postinstall-hook.sh" || fail "a volume with no candidate icon is not a failure"
[ "$(cat "$ICON")" = placeholder ] || fail "with no candidate icon the placeholder stays"
# spec: README.md "The kernel-fixes kext" -- Recaulk retires Wowfunhappy's KQueueScanContinuePatch, which its
#       kqueue_scan_restart replaces: on any target volume his kext and its LaunchDaemon go
WK="$V/Library/Extensions/KQueueScanContinuePatch.kext/Contents"
WD="$V/Library/LaunchDaemons/wowfunhappy.KQueueScanContinuePatch-loader.plist"
mkdir -p "$WK" "$(dirname "$WD")"
printf 'plist\n' > "$WK/Info.plist"; printf 'daemon\n' > "$WD"
printf 'other\n' > "$V/Library/LaunchDaemons/someone.else.plist"
ROOT="$V" sh "$R/packaging/postinstall-hook.sh" || fail "the hook must succeed with his kext present"
[ ! -e "$V/Library/Extensions/KQueueScanContinuePatch.kext" ] || fail "his kext is still there"
[ ! -e "$WD" ] || fail "his LaunchDaemon is still there"
[ -f "$V/Library/LaunchDaemons/someone.else.plist" ] || fail "another LaunchDaemon went too"
ROOT="$V" sh "$R/packaging/postinstall-hook.sh" || fail "the hook must succeed with his kext already gone"
echo "OK: the postinstall hook swaps the updater icon from the target volume and retires KQueueScanContinuePatch"
