#!/bin/sh
# platform: macOS-only -- compiles probes with clang22 against the pinned 10.9 SDK.
# spec: README.md "SDK declaration metadata" -- every recipe is proved by a probe that compiles with
#       -Werror through the recipe's overlay and fails without it, so no recipe is a no-op and none
#       breaks the header it edits. tests/fixtures/sdk-probes/<id>.m is the probe; a "// needs:" line names
#       other recipe ids it also needs, and a "// weak:" line names symbols of APIs 10.9 lacks, which must
#       be weak references in the probe's object so a binary using them still loads on 10.9. A "// ast: FILTER
#       REGEX" line proves what compiling cannot (a getter redeclared as a property, a bridged CF type): clang's
#       AST dump of FILTER matches REGEX through the overlay and does not on the SDK alone; a probe with such
#       lines may itself compile without the recipe.
set -eu
cd "$(dirname "$0")/.."
. build/msc.sh
SC="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
for c in /usr/local/mavergreen/clang22/bin/clang /usr/local/mavergreen/clang22-cross/bin/clang; do
  [ -x "$c" ] && CLANG22=$c && break
done
[ -n "${CLANG22:-}" ] || { echo "FAIL: no installed clang22"; exit 1; }
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
MODULES=$(dirname "$SHIPYARD_SCRIPTS")
fail=0
bad() { echo "FAIL: $*"; fail=1; }
d="$(mktemp -d "${TMPDIR:-/tmp}/sdk-metadata-compile.XXXXXX")"
trap 'rm -rf "$d"' EXIT
ids=$("$SC" -DRECIPES="$PWD/sdk-metadata/recipes.json" -P tests/fixtures/sdk-metadata-ids.cmake 2>&1) \
  || { echo "FAIL: cannot list recipe ids: $ids"; exit 1; }
for p in tests/fixtures/sdk-probes/*.m; do
  printf '%s\n' "$ids" | grep -qx "$(basename "$p" .m)" || bad "$(basename "$p" .m) has a probe but no recipe"
done
# platform: SDK_METADATA_ONLY limits the run to the named recipe ids, for working on one probe
[ -n "${SDK_METADATA_ONLY:-}" ] && ids=$SDK_METADATA_ONLY
# platform: each recipe's probe is independent, so they run SDK_METADATA_JOBS at a time (default 4); their
#   reports print in id order afterwards
export SC MODULES SDK CLANG22 d
printf '%s\n' $ids | xargs -P "${SDK_METADATA_JOBS:-4}" -n 1 sh tests/fixtures/sdk-metadata-compile-one.sh
for id in $ids; do
  [ -f "$d/$id.out" ] && cat "$d/$id.out"
  [ -f "$d/$id.fail" ] && fail=1
done
[ "$fail" -eq 0 ] && echo "sdk-metadata-compile OK"
exit "$fail"
