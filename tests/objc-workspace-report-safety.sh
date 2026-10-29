#!/bin/sh
# platform: macOS-only -- oracle report paths must not overwrite or follow symlinks
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/workspace-report-safety.XXXXXX")
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
mkdir "$T/scripts" "$T/existing" "$T/target"
printf 'unrelated\n' > "$T/existing/build-identity.txt"
printf '#!/bin/sh\n: > "$SAFETY_PREREQUISITE_CALLED"\nexit 1\n' > "$T/scripts/fetch_sdk.sh"
ln -s "$T/target" "$T/link"
export SAFETY_PREREQUISITE_CALLED="$T/called"
for path in "$T/existing" "$T/link" "$T/link/new"; do
 rm -f "$T/called"
 rc=0
 SHIPYARD_SCRIPTS="$T/scripts" sh "$ROOT/tests/objc-workspace-reference.sh" --report "$path" > "$T/log" 2>&1 || rc=$?
 [ "$rc" = 1 ] && [ ! -e "$T/called" ] || { echo "FAIL: unsafe report accepted before prerequisite work: $path"; exit 1; }
done
[ "$(/usr/bin/stat -f %z "$T/existing/build-identity.txt")" = 10 ] || exit 1
[ ! -e "$T/target/new" ] || exit 1
# A fresh output directory is permitted, but the fake prerequisite must fail.
rc=0
SHIPYARD_SCRIPTS="$T/scripts" sh "$ROOT/tests/objc-workspace-reference.sh" --report "$T/private report" > "$T/log" 2>&1 || rc=$?
[ "$rc" = 1 ] && [ -e "$T/called" ] && [ -d "$T/private report" ] || exit 1
[ "$(/usr/bin/stat -f %Lp "$T/private report")" = 700 ] || { echo 'FAIL: report directory is not private'; exit 1; }
echo 'report safety: existing outputs and symlink components refused; fresh output is private'
