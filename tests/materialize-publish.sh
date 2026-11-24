#!/bin/sh
# platform: host-agnostic
# spec: README.md "Materializing an SDK view" "Output layout", "Stamp and caching",
#       "Concurrency and atomicity", "Consumer review" -- the published tree, its identity and its one-rename publish
set -eu
cd "$(dirname "$0")/.."
F="$PWD/tests/fixtures/materialize"
d="$(mktemp -d "${TMPDIR:-/tmp}/materialize-publish.XXXXXX")"
trap 'chmod -R u+w "$d" 2>/dev/null; rm -rf "$d"' EXIT
d="$(cd -P "$d" && pwd -P)"   # platform: macOS's TMPDIR is behind /var -> /private/var; keep "given" and "real" distinct only where the test says so
fail=0
bad() { echo "FAIL: $*"; fail=1; }
sh build/build-materialize.sh host "$d/rm"
sh "$F/make-sdk.sh" "$d/s"
REAL="$d/s/MacOSX10.9.sdk"
GIVEN="$d/given.sdk"; ln -s "$REAL" "$GIVEN"
mz() { "$d/rm" --recipes "$F/recipes.json" --profiles "$F/profiles.json" "$@" >"$d/stdout" 2>"$d/err" && rc=0 || rc=$?; }
refuse() {
  what="$1"; shift
  [ "$rc" = 1 ] || { bad "$what: exited $rc, want 1 ($(cat "$d/err"))"; return; }
  [ "$(wc -l <"$d/err" | tr -d ' ')" = 1 ] || bad "$what: more than one stderr line"
  for w in "$@"; do grep -qF -- "$w" "$d/err" || bad "$what: stderr lacks '$w': $(cat "$d/err")"; done
}
mode() { ls -ld "$1" | cut -c1-10; }

echo "== layout"
O="$d/o1"
mz --sdk "$GIVEN" --out "$O" --profile t
[ "$rc" = 0 ] || bad "the fixture profile exited $rc: $(cat "$d/err")"
V="$O/sdk/MacOSX10.9.sdk"
for e in System usr SDKSettings.plist; do
  [ -L "$V/$e" ] && [ "$(readlink "$V/$e")" = "$REAL/$e" ] || bad "$V/$e is not a link to $REAL/$e"
done
[ "$(cd "$V" && ls -A | tr '\n' ' ')" = "SDKSettings.json SDKSettings.plist System usr " ] || bad "the SDK view holds $(cd "$V" && ls -A)"
printf '{"CanonicalName":"macosx10.9","MaximumDeploymentTarget":"10.9","Version":"10.9"}\n' > "$d/settings.want"
[ -f "$V/SDKSettings.json" ] && [ ! -L "$V/SDKSettings.json" ] && cmp -s "$V/SDKSettings.json" "$d/settings.want" \
  || bad "SDKSettings.json is not the pinned settings"
cmp -s "$O/headers/System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSArray.h" "$F/NSArray.expected.h" \
  || bad "the rewritten NSArray.h is not NSArray.expected.h"
[ "$(mode "$O")" = drwxr-xr-x ] && [ "$(mode "$O/headers/usr/include")" = drwxr-xr-x ] || bad "directories are not 0755"
[ "$(mode "$O/headers/usr/include/stdio.h")" = -rw-r--r-- ] && [ "$(mode "$O/stamp.json")" = -rw-r--r-- ] \
  && [ "$(mode "$V/SDKSettings.json")" = -rw-r--r-- ] || bad "files are not 0644"

echo "== existing_sdksettings_json_is_linked"
sh "$F/make-sdk.sh" "$d/s3"; printf '{"x":1}\n' > "$d/s3/MacOSX10.9.sdk/SDKSettings.json"
mz --sdk "$d/s3/MacOSX10.9.sdk" --out "$d/o3j" --profile t
[ "$rc" = 0 ] && [ -L "$d/o3j/sdk/MacOSX10.9.sdk/SDKSettings.json" ] || bad "an SDK's own SDKSettings.json was not linked"

echo "== overlay_three_roots (RF5)"
grep -q '"case-sensitive":"true"' "$O/overlay.json" || bad "the overlay is not case-sensitive"
[ "$(grep -o '"name":' "$O/overlay.json" | wc -l | tr -d ' ')" = 9 ] || bad "the overlay does not have 3 names x 3 roots"
for root in "$V" "$GIVEN" "$REAL"; do
  for n in usr/include/stdio.h System/Library/Frameworks/Foundation.framework/Headers/NSArray.h; do
    grep -qF "\"name\":\"$root/$n\"" "$O/overlay.json" || bad "the overlay lacks $root/$n"
  done
done
grep -qF "\"external-contents\":\"$O/headers/usr/include/stdio.h\"" "$O/overlay.json" || bad "stdio.h does not map into headers/"
mz --sdk "$REAL" --out "$d/oreal" --profile t
[ "$(grep -o '"name":' "$d/oreal/overlay.json" | wc -l | tr -d ' ')" = 6 ] || bad "the SDK given by its real path did not dedupe names"

echo "== stamp"
grep -qF '"profile":"t","ids":["t-array-v1","t-stdio-v1"],' "$O/stamp.json" || bad "the stamp's profile and ids: $(cat "$O/stamp.json")"
grep -qF "\"sdk\":\"$REAL\"" "$O/stamp.json" || bad "the stamp does not record the SDK's real path"
grep -qF "\"given\":\"$GIVEN\",\"out\":\"$O\"" "$O/stamp.json" || bad "the stamp does not record the SDK as given and --out"
grep -qF '"archive":"fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0"' "$O/stamp.json" \
  || bad "the stamp does not record the recipes' SDK archive pin"
grep -qF '"headers/usr/include/stdio.h":"' "$O/stamp.json" || bad "the stamp's files lack headers/usr/include/stdio.h"
[ "$(wc -l < "$O/stamp.json" | tr -d ' ')" = 1 ] || bad "the stamp is not one line"

echo "== print_stamp"
"$d/rm" --print-stamp --profile t --recipes "$F/recipes.json" --profiles "$F/profiles.json" > "$d/ps"
sed -e 's/"recaulk":"[^"]*",//' -e 's/,"sdk":.*$/}/' "$O/stamp.json" > "$d/ps.want"
cmp -s "$d/ps" "$d/ps.want" || bad "--print-stamp printed $(cat "$d/ps"), want $(cat "$d/ps.want")"
grep -q '"sdk"\|"recaulk"' "$d/ps" && bad "--print-stamp carries sdk or recaulk"

echo "== deterministic"
mz --sdk "$GIVEN" --out "$d/o2" --profile t
# spec: README.md "Materializing an SDK view" -- byte-identical per --out; the stamp's files hash overlay.json, which names --out
for f in overlay.json stamp.json; do
  sed -e "s|$O|OUT|g" -e 's/,"files":.*$//' "$O/$f" > "$d/a"; sed -e "s|$d/o2|OUT|g" -e 's/,"files":.*$//' "$d/o2/$f" > "$d/b"
  cmp -s "$d/a" "$d/b" || bad "$f differs between two --out with the same inputs"
done
diff -r "$O/headers" "$d/o2/headers" >/dev/null || bad "headers differ between two --out"
cp "$O/overlay.json" "$O/stamp.json" "$d/"; rm -rf "$O"
mz --sdk "$GIVEN" --out "$O" --profile t
cmp -s "$O/overlay.json" "$d/overlay.json" && cmp -s "$O/stamp.json" "$d/stamp.json" || bad "the same --out twice is not byte-identical"

echo "== golden (format discipline)"
rel() { sed -e "s|$O|OUT|g" -e "s|$REAL|SDK|g" -e "s|$GIVEN|GIVEN|g" -e 's/"recaulk":"[^"]*"/"recaulk":"VER"/' "$1"; }
mkdir -p "$d/golden"
# spec: README.md "Materializing an SDK view" -- the golden stamp drops files (they hash overlay.json, which names --out)
rel "$O/stamp.json" | sed 's/,"files":.*$/}/' > "$d/golden/stamp.json"; rel "$O/overlay.json" > "$d/golden/overlay.json"
(cd "$O" && find . | LC_ALL=C sort) > "$d/golden/tree.txt"
cp "$V/SDKSettings.json" "$d/golden/SDKSettings.json"
if [ "${MATERIALIZE_REGEN_GOLDEN:-}" = 1 ]; then rm -rf "$F/golden"; cp -R "$d/golden" "$F/golden"; fi
if ! diff -r "$F/golden" "$d/golden" >/dev/null 2>&1; then
  if grep -qF "$(grep -o '"format":[0-9]*' "$d/golden/stamp.json")" "$F/golden/stamp.json" 2>/dev/null; then
    bad "the output changed but format did not: bump MZ_FORMAT, then MATERIALIZE_REGEN_GOLDEN=1 sh $0"
  else
    bad "format changed: regenerate the golden tree with MATERIALIZE_REGEN_GOLDEN=1 sh $0"
  fi
fi

echo "== fast_path"
ls -id "$O/stamp.json" > "$d/inode"
chmod -R a-w "$O"
mz --sdk "$GIVEN" --out "$O" --profile t
[ "$rc" = 0 ] || bad "a matching --out exited $rc: $(cat "$d/err")"
ls -id "$O/stamp.json" | cmp -s - "$d/inode" || bad "a matching --out was replaced"
chmod -R u+w "$O"

echo "== mismatch"
mz --sdk "$GIVEN" --out "$O" --recipe t-stdio-v1
refuse other_profile "$O" profile
sh "$F/make-sdk.sh" "$d/s2"
mz --sdk "$d/s2/MacOSX10.9.sdk" --out "$O" --profile t
refuse other_sdk "$O" sdk

echo "== identity_names_the_sdk_spelling_and_out (review I1)"
mz --sdk "$REAL" --out "$O" --profile t
refuse other_spelling "$O" given
mv "$O" "$d/moved"
mz --sdk "$GIVEN" --out "$d/moved" --profile t
refuse moved_out "$d/moved" out
mv "$d/moved" "$O"

echo "== never_inside_the_sdk (review I3)"
mz --sdk "$GIVEN" --out "$REAL/usr/view" --profile t
refuse inside_sdk 'inside the SDK'
mz --sdk "$GIVEN" --out "$GIVEN/v2" --profile t
refuse inside_sdk_via_link 'inside the SDK'
[ ! -e "$REAL/usr/view" ] && [ ! -e "$REAL/v2" ] && [ -z "$(ls -d "$REAL"/v2.tmp.* "$REAL"/usr/view.tmp.* 2>/dev/null)" ] \
  || bad "a refused --out inside the SDK wrote into it"

echo "== verify"
printf ' ' >> "$O/headers/usr/include/stdio.h"
mz --sdk "$GIVEN" --out "$O" --profile t
[ "$rc" = 0 ] || bad "without --verify a tampered tree was refused"
mz --sdk "$GIVEN" --out "$O" --profile t --verify
refuse verify usr/include/stdio.h

echo "== verify_sees_extra_files_and_links (review M13)"
O2="$d/o-verify"
mz --sdk "$GIVEN" --out "$O2" --profile t
: > "$O2/headers/usr/include/extra.h"
mz --sdk "$GIVEN" --out "$O2" --profile t --verify
refuse verify_extra_file headers/usr/include/extra.h
rm "$O2/headers/usr/include/extra.h"
mz --sdk "$GIVEN" --out "$O2" --profile t --verify
[ "$rc" = 0 ] || bad "--verify refused an untouched tree: $(cat "$d/err")"
rm "$O2/sdk/MacOSX10.9.sdk/usr"; ln -s /usr "$O2/sdk/MacOSX10.9.sdk/usr"
mz --sdk "$GIVEN" --out "$O2" --profile t --verify
refuse verify_link sdk/MacOSX10.9.sdk/usr

echo "== trailing_slash_names_the_link (review M14)"
ln -s "$O2" "$d/olink"
mz --sdk "$GIVEN" --out "$d/olink/" --profile t
refuse trailing_slash 'symbolic link'

echo "== settings_json_escapes (review M10)"
sh "$F/make-sdk.sh" "$d/s4"
P4="$d/s4/MacOSX10.9.sdk/SDKSettings.plist"
sed 's|<string>OS X 10.9</string>|<string>OS X 10.9</string>|; s|^\(	<key>Version</key>\)$|\1|' "$P4" > "$d/p4"
awk '/<key>Version<\/key>/ { print; getline; print "	<string>10.9 \"b\" \\ 1</string>"; next } { print }' "$d/p4" > "$P4"
mz --sdk "$d/s4/MacOSX10.9.sdk" --out "$d/o-settings" --profile t
[ "$rc" = 0 ] || bad "a Version holding a quote and a backslash was refused: $(cat "$d/err")"
grep -qF '"Version":"10.9 \"b\" \\ 1"' "$d/o-settings/sdk/MacOSX10.9.sdk/SDKSettings.json" \
  || bad "SDKSettings.json does not escape the Version: $(cat "$d/o-settings/sdk/MacOSX10.9.sdk/SDKSettings.json")"

echo "== out_refusals (RF3)"
mz --sdk "$GIVEN" --out "$d/nope/out" --profile t
refuse missing_parent "$d/nope"
[ ! -e "$d/nope" ] || bad "a missing parent was created"
ln -s "$d/dangling-target" "$d/dangle"
mz --sdk "$GIVEN" --out "$d/dangle" --profile t
refuse dangling "$d/dangle"
mkdir "$d/empty"
mz --sdk "$GIVEN" --out "$d/empty" --profile t
refuse empty_dir "$d/empty"

echo "== race (RF4)"
for i in 1 2 3 4; do
  "$d/rm" --recipes "$F/recipes.json" --profiles "$F/profiles.json" --sdk "$GIVEN" --out "$d/race" --profile t \
    >/dev/null 2>"$d/race.$i" & eval "p$i=\$!"
done
for i in 1 2 3 4; do eval "wait \$p$i" || bad "racer $i exited nonzero: $(cat "$d/race.$i")"; done
[ -f "$d/race/stamp.json" ] || bad "no tree after the race"
[ -z "$(ls -d "$d"/race.tmp.* 2>/dev/null)" ] || bad "the race left a staging tree"

echo "== failure_leaves_nothing"
printf ' ' >> "$REAL/usr/include/stdio.h"
mz --sdk "$GIVEN" --out "$d/o4" --profile t
refuse refused_recipe SHA-256
[ ! -e "$d/o4" ] && [ -z "$(ls -d "$d"/o4.tmp.* 2>/dev/null)" ] || bad "a refusal left something at --out"
[ "$fail" = 0 ] && echo "materialize-publish OK"
exit "$fail"
