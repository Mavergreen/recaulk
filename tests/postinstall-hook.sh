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
# spec: README.md "The kernel-fixes kext" -- the postinstall lists RecaulkKernelFixes, at its installed version, in the
#       target volume's OSKextSigExceptionList so 10.9's kextd loads it unsigned; the pre-uninstall hook removes it
XL="$V/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist"
KI="$V/Library/Extensions/RecaulkKernelFixes.kext/Contents/Info.plist"
LX="$V/usr/local/mavergreen/recaulk/libexec/recaulk"
mkdir -p "$(dirname "$XL")" "$(dirname "$KI")" "$LX"
cp "$R/packaging/kext-exception.sh" "$LX/kext-exception.sh"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>OSKextSigExceptionList</key>\n\t<dict>\n\t\t<key>anon.tap</key>\n\t\t<string>1.0</string>\n\t</dict>\n</dict>\n</plist>\n' > "$XL"
cp "$XL" "$t/xl.orig"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>CFBundleIdentifier</key>\n\t<string>dev.mavergreen.recaulk.kernelfixes</string>\n\t<key>CFBundleVersion</key>\n\t<string>2611.23.5</string>\n</dict>\n</plist>\n' > "$KI"
ROOT="$V" sh "$R/packaging/postinstall-hook.sh" || fail "the hook must succeed with the exclude list present"
grep -A1 '<key>dev.mavergreen.recaulk.kernelfixes</key>' "$XL" | grep -q '<string>2611.23.5</string>' \
  || fail "the postinstall did not list RecaulkKernelFixes 2611.23.5 in OSKextSigExceptionList: $(cat "$XL")"
MAVERGREEN_ROOT="$V/" sh "$R/packaging/pre-uninstall.sh" || fail "the pre-uninstall hook must succeed"
cmp -s "$XL" "$t/xl.orig" || fail "the pre-uninstall hook did not restore the exclude list: $(cat "$XL")"
MAVERGREEN_ROOT="$V/" sh "$R/packaging/pre-uninstall.sh" || fail "the pre-uninstall hook must succeed with no entry"
echo "OK: the postinstall hook swaps the updater icon from the target volume, retires KQueueScanContinuePatch and lists RecaulkKernelFixes as an allowed unsigned kext; the pre-uninstall hook unlists it"
