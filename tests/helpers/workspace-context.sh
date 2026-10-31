#!/bin/sh
# platform: macOS-only -- stable app-hosted context preparation/verification, no automatic consent
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
: "${SHIPYARD_SCRIPTS:?select pinned shipyard scripts}"
case "${1:-}" in
 --prepare-context|--verify-context) [ "$#" = 2 ] || exit 2; operation=$1; C=$2; report='' ;;
 --context|--authorize-context|--preflight-context)
  operation=$1; C=$2; report=''
  if [ "$#" = 4 ] && [ "$3" = --report ]; then report=$4
  elif [ "$#" != 2 ] || [ "$operation" != --context ]; then exit 2; fi ;;
 --self-test) [ "$#" = 1 ] || exit 2; operation=$1; C=''; report='' ;;
 *) echo 'usage: --prepare-context NEW_DIR | --verify-context DIR | --context|--authorize-context|--preflight-context DIR --report NEW_DIR | --self-test' >&2; exit 2 ;;
esac
safe_path() {
 case "$1" in /*) p=$1 ;; *) p="$PWD/$1" ;; esac
 while [ "$p" != / ]; do [ ! -L "$p" ] || { echo "unsafe symlink component $p" >&2; return 1; }; p=$(dirname "$p"); done
}
safe_path "${C:-$ROOT}"
if [ "$operation" != --self-test ]; then
 case "$C" in /*) ;; *) C="$PWD/$C" ;; esac
fi
fingerprint() {
 (cd "$ROOT" && /usr/bin/shasum -a 256 tests/c/objc_workspace_reference.m tests/c/objc_workspace_context.m tests/c/objc_workspace_probe_app.m tests/fixtures/workspace-probe-Info.plist.in tests/helpers/workspace-context.sh tests/objc-workspace-reference.sh) | /usr/bin/shasum -a 256 | awk '{print $1}'
}
source_id=$(fingerprint)
commit=$(git -C "$ROOT" rev-parse HEAD)
arch=$(uname -m)
case "$arch" in
 arm64) floor=11.0; sdk_arch=arm64 ;;
 x86_64)
  floor=10.9; sdk_arch=x86_64
  if [ "$operation" != --self-test ]; then
   version=$(sw_vers -productVersion); major=${version%%.*}; rest=${version#*.}; minor=${rest%%.*}
   if [ "$major" -gt 10 ] || { [ "$major" = 10 ] && [ "$minor" -ge 14 ]; }; then
    # Reference SDK 11.3 is explicitly selected for the modern sender's public
    # no-prompt API, while emitting a native x86_64 binary. Not a floor build.
    floor=10.14; sdk_arch=arm64
   else echo 'stable Automation context requires macOS >=10.14' >&2; exit 1; fi
  fi ;;
 *) exit 1 ;;
esac
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-context-build.XXXXXX")
trap 'rm -rf "$T"' EXIT
manifest() {
 # Known signed roots only; never interpret paths supplied by a checksum file.
 [ -d "$C/Sender.app" ] && [ -d "$C/Probe.app" ] || return 1
 [ -z "$(find "$C/Sender.app" "$C/Probe.app" -type l -print)" ] || return 1
 find "$C/Sender.app" "$C/Probe.app" -type f -print | LC_ALL=C sort | while IFS= read -r f; do /usr/bin/shasum -a 256 "$f"; done
}
verify() {
 [ -d "$C" ] && [ "$(/usr/bin/stat -f %u "$C")" = "$(id -u)" ] && [ "$(/usr/bin/stat -f %Lp "$C")" = 700 ] || { echo 'context must be caller-owned/private' >&2; return 1; }
 [ "$(/bin/cat "$C/context.path")" = "$C" ] && [ "$(/bin/cat "$C/source.sha256")" = "$source_id" ] && [ "$(/bin/cat "$C/source.commit")" = "$commit" ] && [ "$(/bin/cat "$C/architecture")" = "$arch" ] || { echo 'context does not match current source/commit/path/architecture' >&2; return 1; }
 [ "$(/bin/cat "$C/sdk.path")" = "$SDK" ] || { echo 'pinned SDK path changed' >&2; return 1; }
 /usr/bin/shasum -a 256 "$SDK/SDKSettings.plist" > "$T/sdk.sha256"
 cmp "$T/sdk.sha256" "$C/sdk.sha256" || return 1
 /usr/bin/shasum -a 256 "$SHIPYARD_SCRIPTS/fetch_sdk.sh" > "$T/sdk-fetch.sha256"
 cmp "$T/sdk-fetch.sha256" "$C/sdk-fetch.sha256" || return 1
 /usr/bin/clang --version > "$T/compiler.txt"
 cmp "$T/compiler.txt" "$C/compiler.txt" || return 1
 manifest > "$T/apps.sha256"
 cmp "$T/apps.sha256" "$C/apps.sha256" || { echo 'signed context inputs changed' >&2; return 1; }
 /usr/bin/codesign --verify --strict "$C/Sender.app"
 /usr/bin/codesign --verify --strict "$C/Probe.app"
 echo "verified stable context $C"
}
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$sdk_arch")
if [ "$operation" = --verify-context ]; then verify; exit; fi
if [ "$operation" != --prepare-context ] && [ "$operation" != --self-test ]; then verify; fi
unit_flag=''
[ "$operation" != --self-test ] || unit_flag=-DWORKSPACE_CONTEXT_UNIT_TESTS
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -Wno-deprecated-declarations $unit_flag -DCONTEXT_SOURCE_ID="\"$source_id\"" "$ROOT/tests/c/objc_workspace_context.m" -o "$T/driver" -framework AppKit -framework Carbon
if [ "$operation" = --self-test ]; then "$T/driver" self-test "$T"; exit; fi
if [ "$operation" = --prepare-context ]; then
 mkdir -m 700 "$C" || { echo 'context must be new' >&2; exit 1; }
 token=$(/usr/bin/uuidgen | tr 'A-Z' 'a-z')
 mkdir -p "$C/Sender.app/Contents/MacOS" "$C/Probe.app/Contents/MacOS" "$C/events"
 cp "$T/driver" "$C/Sender.app/Contents/MacOS/WorkspaceSender"
 /usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc "$ROOT/tests/c/objc_workspace_probe_app.m" -o "$C/Probe.app/Contents/MacOS/WorkspaceProbe" -framework AppKit -framework Carbon
 cp "$ROOT/tests/fixtures/workspace-probe-Info.plist.in" "$C/Probe.app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c "Set :WorkspaceProbeReportDirectory $C/events" "$C/Probe.app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.mavergreen.workspace.context.probe.$token" "$C/Probe.app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c 'Set :CFBundleName Mavergreen Stable Workspace Fixture' "$C/Probe.app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Mavergreen Stable Workspace Fixture' "$C/Probe.app/Contents/Info.plist"
 P="$C/Sender.app/Contents/Info.plist"
 /usr/bin/plutil -create xml1 "$P"
 for spec in 'CFBundleExecutable string WorkspaceSender' 'CFBundleName string Mavergreen Stable Workspace Sender' 'CFBundleDisplayName string Mavergreen Stable Workspace Sender' 'CFBundlePackageType string APPL' 'CFBundleVersion string 1' 'NSPrincipalClass string NSApplication'; do /usr/libexec/PlistBuddy -c "Add :$spec" "$P"; done
 /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string org.mavergreen.workspace.context.sender.$token" "$P"
 /usr/libexec/PlistBuddy -c "Add :WorkspaceContextDirectory string $C" "$P"
 /usr/libexec/PlistBuddy -c 'Add :NSAppleEventsUsageDescription string This dedicated test sender requests control only of its private Mavergreen Stable Workspace Fixture for native launch-contract tests. It does not control real applications.' "$P"
 /usr/bin/codesign --force --sign - "$C/Probe.app"
 /usr/bin/codesign --force --sign - "$C/Sender.app"
 printf '%s\n' "$C" > "$C/context.path"; printf '%s\n' "$source_id" > "$C/source.sha256"
 printf '%s\n' "$commit" > "$C/source.commit"; printf '%s\n' "$arch" > "$C/architecture"
 printf '%s\n' "$SDK" > "$C/sdk.path"
 /usr/bin/shasum -a 256 "$SDK/SDKSettings.plist" > "$C/sdk.sha256"
 /usr/bin/clang --version > "$C/compiler.txt"
 /usr/bin/shasum -a 256 "$SHIPYARD_SCRIPTS/fetch_sdk.sh" > "$C/sdk-fetch.sha256"
 manifest > "$C/apps.sha256"
 /usr/bin/codesign -dvv "$C/Sender.app" 2> "$C/sender-signature.txt"
 /usr/bin/codesign -dvv "$C/Probe.app" 2> "$C/probe-signature.txt"
 verify
 "$T/driver" describe "$C"
 echo 'PREPARED ONLY: no permission request was made'
 exit
fi
[ -n "$report" ] || report="$T/report"
safe_path "$report"
case "$operation" in --context) op=run ;; --authorize-context) op=authorize ;; --preflight-context) op=preflight ;; esac
child=''
forward() { trap '' INT TERM HUP; if [ -n "$child" ]; then kill -"$1" "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; else wait 2>/dev/null || :; fi; exit 130; }
trap 'forward INT' INT
trap 'forward TERM' TERM
trap 'forward HUP' HUP
"$T/driver" launch "$C" "$op" "$report" &
child=$!
rc=0; wait "$child" || rc=$?
child=''
exit "$rc"
