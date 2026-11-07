#!/bin/sh
# platform: macOS-only -- compiles probes with clang22 against the pinned 10.9 SDK.
# spec: README.md "SDK declaration metadata" -- every recipe is proved by a probe that compiles with
#       -Werror through the recipe's overlay and fails without it, so no recipe is a no-op and none
#       breaks the header it edits. tests/fixtures/sdk-probes/<id>.m is the probe; a "// needs:" line names
#       other recipe ids it also needs, and a "// weak:" line names symbols of APIs 10.9 lacks, which must
#       be weak references in the probe's object so a binary using them still loads on 10.9.
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
for id in $ids; do
  probe="tests/fixtures/sdk-probes/$id.m"
  [ -f "$probe" ] || { bad "$id has no probe $probe"; continue; }
  need=$(sed -n 's|^// needs: ||p' "$probe")
  sel=$(printf '%s;%s' "$id" "$need" | sed 's/;$//; s/ /;/g')
  if ! ov=$("$SC" -DMODULES="$MODULES" -DSDK="$SDK" -DRECIPES="$PWD/sdk-metadata/recipes.json" -DIDS="$sel" \
              -DOUT="$d/$id" -P tests/fixtures/sdk-metadata-materialize.cmake 2>&1); then
    bad "$id does not materialize: $ov"; continue
  fi
  ov=$(printf '%s\n' "$ov" | tail -1)
  flags="-fsyntax-only -Werror -x objective-c -fno-objc-arc -arch x86_64 -mmacosx-version-min=10.9 -isysroot $SDK"
  # shellcheck disable=SC2086
  "$CLANG22" $flags -ivfsoverlay "$ov" "$probe" >"$d/$id.with" 2>&1 \
    || { bad "$id: its probe does not compile through the overlay"; sed 's/^/    /' "$d/$id.with" | head -8; }
  # shellcheck disable=SC2086
  "$CLANG22" $flags "$probe" >"$d/$id.without" 2>&1 && bad "$id: its probe compiles without the recipe (a no-op recipe)"
  weak=$(sed -n 's|^// weak: ||p' "$probe")
  if [ -n "$weak" ]; then
    # shellcheck disable=SC2086
    "$CLANG22" $(printf '%s' "$flags" | sed 's/-fsyntax-only/-c/') -ivfsoverlay "$ov" -o "$d/$id.o" "$probe" >/dev/null 2>&1 \
      || { bad "$id: its probe does not compile to an object"; continue; }
    for sym in $weak; do
      "$(dirname "$CLANG22")/llvm-nm" -m "$d/$id.o" | awk -v s="$sym" '$1 == "(undefined)" && $2 == "weak" && $3 == "external" && $4 == s { f = 1 } END { exit !f }' \
        || bad "$id: $sym is not a weak reference, so the binary would not load on 10.9"
    done
  fi
done
[ "$fail" -eq 0 ] && echo "sdk-metadata-compile OK"
exit "$fail"
