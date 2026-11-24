#!/bin/sh
# platform: host-agnostic -- the pinned 10.9 SDK, clang22, and shipyard's module through shipyard-cmake (or cmake)
# spec: README.md "Materializing an SDK view" "Constraints" -- shipyard's
#       MavericksSDKMetadata.cmake is the reference: for each shipped profile, recaulk-materialize writes the same
#       header bytes and maps the same names under the SDK as given; it takes seconds, a cached run less than one,
#       and code compiles through its view whether the sysroot is the view or the SDK itself
set -eu
cd "$(dirname "$0")/.."
. build/lib.sh
recaulk_tools
SC="$(command -v shipyard-cmake || command -v cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
MODULES="$(dirname "$SHIPYARD_SCRIPTS")"
d="$(mktemp -d "${TMPDIR:-/tmp}/materialize-parity.XXXXXX")"
trap 'rm -rf "$d"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
sh build/build-materialize.sh host "$d/rm"
REAL="$(cd -P "$SDK" && pwd -P)"
for profile in swift-foundation swift-appkit; do
  echo "== $profile"
  ids="$(python3 -c 'import json, sys; print(";".join(json.load(open("sdk-metadata/profiles.json"))["profiles"][sys.argv[1]]["recipes"]))' "$profile")"
  "$SC" -DMODULES="$MODULES" -DSDK="$SDK" -DRECIPES="$PWD/sdk-metadata/recipes.json" -DIDS="$ids" -DOUT="$d/module-$profile" \
    -P tests/fixtures/sdk-metadata-materialize.cmake >/dev/null 2>"$d/module.err" \
    || { bad "shipyard's module refused $profile: $(tail -3 "$d/module.err")"; continue; }
  t0=$(date +%s)
  "$d/rm" --sdk "$SDK" --out "$d/rm-$profile" --profile "$profile" --recipes "$PWD/sdk-metadata/recipes.json" \
    --profiles "$PWD/sdk-metadata/profiles.json" 2>"$d/err" || { bad "recaulk-materialize refused $profile: $(cat "$d/err")"; continue; }
  t1=$(date +%s)
  [ $((t1 - t0)) -lt 10 ] || bad "$profile took $((t1 - t0)) s, want under 10"
  "$d/rm" --sdk "$SDK" --out "$d/rm-$profile" --profile "$profile" --recipes "$PWD/sdk-metadata/recipes.json" \
    --profiles "$PWD/sdk-metadata/profiles.json"
  t2=$(date +%s)
  [ $((t2 - t1)) -le 1 ] || bad "a cached $profile took $((t2 - t1)) s, want under 1"

  (cd "$d/module-$profile/headers" && find . -type f | LC_ALL=C sort) > "$d/module.files"
  (cd "$d/rm-$profile/headers" && find . -type f | LC_ALL=C sort) > "$d/rm.files"
  cmp -s "$d/module.files" "$d/rm.files" || bad "$profile: the two rewrite different headers"
  while read -r f; do
    cmp -s "$d/module-$profile/headers/$f" "$d/rm-$profile/headers/$f" || bad "$profile: $f differs from shipyard's module"
  done < "$d/rm.files"
  # spec: README.md "Materializing an SDK view" -- the same names under the SDK as given and its real path, the module's two roots
  for o in module rm; do
    # platform: the module pretty-prints ("name" : "..."), recaulk-materialize writes one entry a line
    tr ',{}' '\n\n\n' < "$d/$o-$profile/overlay.json" | sed -n 's/^ *"name" *: *"\(.*\)" *$/\1/p' \
      | grep -v "^$d/rm-$profile/sdk/" | LC_ALL=C sort -u > "$d/$o.names"
  done
  cmp -s "$d/module.names" "$d/rm.names" || { bad "$profile: the overlays map different names"; diff "$d/module.names" "$d/rm.names" | head -5; }
done

echo "== interrupted_leaves_nothing (review M12)"
# platform: sh starts a background job with SIGINT ignored, so INT cannot reach it here; TERM and HUP take the same path
for sig in TERM HUP; do
  "$d/rm" --sdk "$SDK" --out "$d/int-$sig" --profile swift-appkit --recipes "$PWD/sdk-metadata/recipes.json" \
    --profiles "$PWD/sdk-metadata/profiles.json" 2>"$d/int.err" &
  pid=$!
  while [ -z "$(ls -d "$d/int-$sig".tmp.* 2>/dev/null)" ] && kill -0 "$pid" 2>/dev/null; do :; done
  kill -"$sig" "$pid" 2>/dev/null || true
  wait "$pid" && rc=0 || rc=$?
  if [ "$rc" = 0 ]; then
    echo "   ($sig arrived after it finished; nothing to check)"
  elif [ -s "$d/int.err" ]; then
    bad "the SIG$sig run failed on its own: $(cat "$d/int.err")"
  else
    [ -z "$(ls -d "$d/int-$sig".tmp.* 2>/dev/null)" ] || bad "SIG$sig left $(ls -d "$d/int-$sig".tmp.*)"
    [ ! -e "$d/int-$sig" ] || bad "SIG$sig left a published $d/int-$sig"
  fi
done

echo "== objective_cxx_through_each_profile"
# spec: README.md "Profiles" -- a .mm importing Cocoa compiles through every shipped profile's view, as through the
#       SDK itself: a recipe never declares a C++ keyword (template, class, new...) where C++ can see it
printf '#import <Cocoa/Cocoa.h>\nint main(void) { return NSApplication.sharedApplication != nil; }\n' > "$d/cocoa.mm"
for profile in swift-foundation swift-appkit; do
  "$CC" $TARGET_FLAGS -fsyntax-only -x objective-c++ -fno-objc-arc -fblocks -isysroot "$d/rm-$profile/sdk/MacOSX10.9.sdk" \
    -ivfsoverlay "$d/rm-$profile/overlay.json" "$d/cocoa.mm" >"$d/cxx.out" 2>&1 \
    || { bad "a .mm importing Cocoa does not compile through $profile"; grep -m3 error: "$d/cxx.out"; }
done

echo "== compiles_through_the_view (RF5)"
probe=tests/fixtures/sdk-probes-consumer/appkit-subclasses.m
V="$d/rm-swift-appkit/sdk/MacOSX10.9.sdk"
for sysroot in "$V" "$SDK" "$REAL"; do
  "$CC" $TARGET_FLAGS -fsyntax-only -Werror -Wall -x objective-c -fno-objc-arc -fblocks -isysroot "$sysroot" \
    -ivfsoverlay "$d/rm-swift-appkit/overlay.json" "$probe" >"$d/cc.out" 2>&1 \
    || { bad "$probe does not compile through the view with -isysroot $sysroot"; head -8 "$d/cc.out"; }
done
"$CC" $TARGET_FLAGS -fsyntax-only -Werror -Wall -x objective-c -fno-objc-arc -fblocks -isysroot "$V" "$probe" >/dev/null 2>&1 \
  && bad "$probe compiles without the overlay, so it proves nothing"
[ "$fail" = 0 ] && echo "materialize-parity OK"
exit "$fail"
