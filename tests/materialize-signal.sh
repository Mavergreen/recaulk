#!/bin/sh
# platform: host-agnostic -- the probe preloads with DYLD_INSERT_LIBRARIES on a Mac and LD_PRELOAD on Linux
# spec: README.md "Materializing an SDK view" -- an interrupted run leaves nothing. A signal can land while the
#       materializer is inside malloc (main run 45979186745: glibc "malloc(): invalid size" on SIGHUP), so the
#       handler may only record it: one that allocates while that malloc runs corrupts the heap. The probe raises
#       the signal from inside malloc, at several points after the stage exists, and fails on any reentrant malloc.
set -eu
cd "$(dirname "$0")/.."
. build/lib.sh
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
d="$(mktemp -d "${TMPDIR:-/tmp}/materialize-signal.XXXXXX")"
trap 'rm -rf "$d"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
sh build/build-materialize.sh host "$d/rm"
if [ "$(uname -s)" = Darwin ]; then
  recaulk_tools
  # platform: the probe matches the host-built materializer's arch (build-materialize.sh host)
  case "$(uname -m)" in arm64) t="--target=arm64-apple-macos11.0 -isysroot $(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)" ;;
                        *) t="--target=x86_64-apple-macos10.9 -mmacosx-version-min=10.9 -isysroot $SDK" ;; esac
  # shellcheck disable=SC2086 # t is flags
  "$CC" --no-default-config $t -dynamiclib -O1 -Wall -Werror tests/c/malloc_signal_probe.c -o "$d/probe.dylib"
  PRELOAD=DYLD_INSERT_LIBRARIES; probe="$d/probe.dylib"
else
  ${HOST_CC:-cc} -shared -fPIC -O1 -Wall -Werror tests/c/malloc_signal_probe.c -o "$d/probe.so" -ldl
  PRELOAD=LD_PRELOAD; probe="$d/probe.so"
fi
signalled=0
for after in 2 3 5 10 40 200 1000; do
  for sig in 1 15; do
    out="$d/out-$after-$sig"
    rc=0
    env "$PRELOAD=$probe" RECAULK_PROBE_AFTER="$after" RECAULK_PROBE_SIGNAL="$sig" "$d/rm" --sdk "$SDK" --out "$out" \
      --profile swift-appkit --recipes "$PWD/sdk-metadata/recipes.json" --profiles "$PWD/sdk-metadata/profiles.json" \
      2> "$d/err" || rc=$?
    case "$rc" in
      0) [ -e "$out" ] || bad "allocation $after, signal $sig: exit 0 without publishing $out" ;;
      $((128 + sig)))
        signalled=$((signalled + 1))
        [ ! -e "$out" ] || bad "allocation $after, signal $sig: died of it but left a published $out"
        [ -z "$(ls -d "$out".tmp.* 2>/dev/null)" ] || bad "allocation $after, signal $sig: left $(ls -d "$out".tmp.*)" ;;
      *) bad "allocation $after, signal $sig: exit $rc, not death by signal $sig: $(cat "$d/err")" ;;
    esac
  done
done
[ "$signalled" -gt 0 ] || bad "no run died of its signal, so the probe never fired after the stage existed"
[ "$fail" = 0 ] && echo "materialize-signal OK ($signalled runs died of a signal raised inside malloc)"
exit $fail
