#!/bin/sh
# platform: macOS -- Drydock's strict Objective-C analyzer (drydock-objc analyze) runs on macOS only; elsewhere this skips
# spec: README.md "Dispatch on 10.9" -- a product that links librecaulk.a's dispatch calls passes shipyard's strict
#       compat guard, which refuses a sel_registerName argument it cannot read as one literal (fuse-gg's MFMount,
#       libfuse 2 and macFUSE.framework, Recaulk 20261121.7: attr_key's ternary between two key names)
set -eu
cd "$(dirname "$0")/.."
RECAULK_TEST_PHASE=build
. tests/helpers/built.sh
[ "$(uname -s)" = Darwin ] || { echo "SKIP: the strict analyzer runs on macOS only"; exit 77; }
d="$(mktemp -d "${TMPDIR:-/tmp}/strict-guard-consumer.XXXXXX")"
trap 'rm -rf "$d"' EXIT
mkdir "$d/pin" "$d/root"
printf 'v%s\n' "$(tr -d ' \t\n' < components/drydock/version)" > "$d/pin/version"
cp /usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/components/drydock/linux-sha256 "$d/pin/" 2>/dev/null || :
MAVERGREEN_DRYDOCK_PREFIX="$(sh "$SHIPYARD_SCRIPTS/fetch_drydock.sh" "$d/pin" | tail -1)"
export MAVERGREEN_DRYDOCK_PREFIX
"$CC" $FLAGS -arch x86_64 -Wall -Werror -I"$T/include/recaulk" tests/c/strict_consumer.c "$T/lib/librecaulk.a" -lobjc -o "$d/root/consumer"
rc=0
MAVERGREEN_OBJC_STRICT=1 MAVERGREEN_OBJC_ROOT="$d/root" LIPO="${LIPO:-lipo}" \
  sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$d/root/consumer" > "$d/out" 2>&1 || rc=$?
if [ "$rc" != 0 ]; then echo "FAIL: the strict guard exited $rc on a librecaulk.a dispatch consumer:"; cat "$d/out"; exit 1; fi
echo "strict-guard-consumer OK"
