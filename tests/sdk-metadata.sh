#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
# platform: shipyard-cmake where shipyard's install action put it (on Linux too since shipyard f1c970a), else the host's cmake
SC="$(command -v shipyard-cmake || command -v cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
[ -x "$SC" ] || { echo "FAIL: no shipyard-cmake or cmake"; exit 1; }
# platform: a real cmake, never the launcher: off Darwin shipyard-cmake runs the cmake on PATH, so a stand-in cmake
#           that ran the launcher would run itself until exec fails (E2BIG). The cmake product on macOS, else the host's.
RC=/usr/local/mavergreen/cmake/bin/cmake
[ -x "$RC" ] || RC="$(command -v cmake || :)"

fail=0
bad() { echo "FAIL: $*"; fail=1; }
d="$(mktemp -d "${TMPDIR:-/tmp}/sdk-metadata.XXXXXX")"
trap 'rm -rf "$d"' EXIT

echo "== schema_and_identity, array_replacements"
"$SC" -DRECIPES="$PWD/sdk-metadata/recipes.json" -P tests/fixtures/sdk-metadata-check.cmake \
  || bad "sdk-metadata/recipes.json does not hold the pinned schema, SDK identity and NSArray recipe"

echo "== stage_data_only"
if sh build/stage-sdk-metadata.sh sdk-metadata "$d/staged"; then
  cmp -s sdk-metadata/recipes.json "$d/staged/recipes.json" || bad "staged recipes.json differs from sdk-metadata/recipes.json"
  extra="$(cd "$d/staged" && find . -type f ! -name recipes.json ! -name profiles.json)"
  [ -z "$extra" ] || bad "staging copied more than recipes.json and profiles.json: $extra"
  # spec: README.md "Profiles" -- profiles.json ships beside the recipes it names (profiles_staged)
  cmp -s sdk-metadata/profiles.json "$d/staged/profiles.json" || bad "staged profiles.json differs from sdk-metadata/profiles.json"
  [ "$(ls -l "$d/staged/profiles.json" | cut -c1-10)" = -rw-r--r-- ] || bad "the staged profiles.json is not 0644"
  # platform: the pkg installs this tree as root, and mktemp -d makes 0700 directories; every user
  #           must read the recipes, so the directory is 0755 and the file 0644
  [ "$(ls -ld "$d/staged" | cut -c1-10)" = drwxr-xr-x ] || bad "the staged directory is not 0755: $(ls -ld "$d/staged")"
  [ "$(ls -l "$d/staged/recipes.json" | cut -c1-10)" = -rw-r--r-- ] || bad "the staged recipes.json is not 0644"
else
  bad "stage-sdk-metadata.sh refused the committed recipes"
fi
sh build/stage-sdk-metadata.sh sdk-metadata "$d/staged" 2>/dev/null \
  && bad "stage-sdk-metadata.sh staged into a destination that already exists"

echo "== malformed_data_refused"
good='{"schema":1,"sdk":"MacOSX10.9","sdk_archive_sha256":"fcf88ce8ff0dd3248b97f4eb81c7909f2cc786725de277f4d05a2b935cc49de0","recipes":[RECIPE]}'
r='{"id":"x-v1","header":"A/B.h","sha256":"62c14ca4c2ab6fc0194328585cce9d18aab0b65338bd0aab2146ad9b0053c585","aliases":["C/B.h"],"replacements":[{"old":"a","new":"b"}]}'
refuse() {
  _name="$1" _json="$2"
  mkdir -p "$d/in-$_name"
  printf '%s\n' "$_json" > "$d/in-$_name/recipes.json"
  if sh build/stage-sdk-metadata.sh "$d/in-$_name" "$d/out-$_name" 2>"$d/err-$_name"; then
    bad "$_name: malformed recipes were staged"
  fi
  grep -q "^stage-sdk-metadata: " "$d/err-$_name" || bad "$_name: refused without naming why: $(cat "$d/err-$_name")"
  [ ! -e "$d/out-$_name" ] || bad "$_name: a refused staging left $d/out-$_name behind"
}
sub() { printf '%s' "$good" | sed "s|RECIPE|$1|"; }
refuse wrong-schema "$(sub "$r" | sed 's/"schema":1/"schema":2/')"
refuse wrong-sdk "$(sub "$r" | sed 's/MacOSX10.9/MacOSX10.10/')"
refuse short-archive-hash "$(sub "$r" | sed 's/"sdk_archive_sha256":"fcf8/"sdk_archive_sha256":"/')"
refuse not-json "$(sub "$r" | sed 's/}$//')"
refuse no-recipes "$(printf '%s' "$good" | sed 's|RECIPE||')"
refuse missing-header "$(sub "$(printf '%s' "$r" | sed 's|"header":"A/B.h",||')")"
refuse absolute-header "$(sub "$(printf '%s' "$r" | sed 's|"header":"A/B.h"|"header":"/A/B.h"|')")"
refuse dotdot-alias "$(sub "$(printf '%s' "$r" | sed 's|"C/B.h"|"C/../../B.h"|')")"
refuse upper-hash "$(sub "$(printf '%s' "$r" | sed 's|62c14ca4|62C14CA4|')")"
refuse duplicate-id "$(sub "$r,$r")"
refuse bad-id "$(sub "$(printf '%s' "$r" | sed 's|x-v1|X v1|')")"
refuse unknown-key "$(sub "$(printf '%s' "$r" | sed 's|"aliases"|"eval":"x","aliases"|')")"
refuse empty-replacements "$(sub "$(printf '%s' "$r" | sed 's|\[{"old":"a","new":"b"}\]|[]|')")"
refuse empty-old "$(sub "$(printf '%s' "$r" | sed 's|"old":"a"|"old":""|')")"
refuse identical-old-new "$(sub "$(printf '%s' "$r" | sed 's|"new":"b"|"new":"a"|')")"
# spec: the materializer design's "Consumer review" -- swift's importer overlay owns these paths
refuse reserved-dispatch "$(sub "$(printf '%s' "$r" | sed 's|"header":"A/B.h"|"header":"usr/include/dispatch/dispatch.h"|')")"
refuse reserved-qos-alias "$(sub "$(printf '%s' "$r" | sed 's|"C/B.h"|"usr/include/pthread/qos.h"|')")"
for _e in reserved-dispatch reserved-qos-alias; do
  grep -q reserved "$d/err-$_e" || bad "$_e: the refusal does not say reserved: $(cat "$d/err-$_e")"
done
refuse replacement-extra-key "$(sub "$(printf '%s' "$r" | sed 's|"new":"b"|"new":"b","regex":true|')")"
echo "== profiles_refused"
r2='{"id":"y-v1","header":"A/B.h","sha256":"62c14ca4c2ab6fc0194328585cce9d18aab0b65338bd0aab2146ad9b0053c585","aliases":[],"replacements":[{"old":"a","new":"b"}]}'
r3='{"id":"z-v1","header":"A/C.h","sha256":"62c14ca4c2ab6fc0194328585cce9d18aab0b65338bd0aab2146ad9b0053c585","aliases":[],"replacements":[{"old":"a","new":"b"}]}'
refuse_profile() {
  _name="$1" _json="$2"
  mkdir -p "$d/in-$_name"
  printf '%s\n' "$(sub "$r,$r2,$r3")" > "$d/in-$_name/recipes.json"
  printf '%s\n' "$_json" > "$d/in-$_name/profiles.json"
  if sh build/stage-sdk-metadata.sh "$d/in-$_name" "$d/out-$_name" 2>"$d/err-$_name"; then
    bad "$_name: a malformed profile was staged"
  fi
  grep -q "^stage-sdk-metadata: " "$d/err-$_name" || bad "$_name: refused without naming why: $(cat "$d/err-$_name")"
  [ ! -e "$d/out-$_name" ] || bad "$_name: a refused staging left $d/out-$_name behind"
}
p='{"schema":1,"profiles":{"p":{"description":"d","recipes":[IDS]}}}'
refuse_profile profiles-unknown-id "$(printf '%s' "$p" | sed 's|IDS|"x-v1","nope-v1"|')"
refuse_profile profiles-two-per-header "$(printf '%s' "$p" | sed 's|IDS|"x-v1","y-v1"|')"
refuse_profile profiles-wrong-schema "$(printf '%s' "$p" | sed 's|IDS|"x-v1"|; s|"schema":1|"schema":2|')"
refuse_profile profiles-empty "$(printf '%s' "$p" | sed 's|IDS||')"
refuse_profile profiles-unknown-key "$(printf '%s' "$p" | sed 's|IDS|"x-v1"|; s|"description"|"extra":1,"description"|')"
refuse_profile profiles-duplicate-id "$(printf '%s' "$p" | sed 's|IDS|"x-v1","x-v1"|')"
# spec: the materializer design's "Layering" -- a profile may name its base, and carries all of the base's ids
q='{"schema":1,"profiles":{"a":{"description":"d","recipes":["x-v1"]},"b":{"description":"d",BASE"recipes":[IDS]}}}'
refuse_profile profiles-base-not-string "$(printf '%s' "$q" | sed 's|BASE|"base":1,|; s|IDS|"x-v1","z-v1"|')"
refuse_profile profiles-base-unknown "$(printf '%s' "$q" | sed 's|BASE|"base":"nope",|; s|IDS|"x-v1","z-v1"|')"
refuse_profile profiles-base-self "$(printf '%s' "$q" | sed 's|BASE|"base":"b",|; s|IDS|"x-v1","z-v1"|')"
refuse_profile profiles-base-missing-id "$(printf '%s' "$q" | sed 's|BASE|"base":"a",|; s|IDS|"z-v1"|')"
refuse_profile profiles-base-cycle "$(printf '%s' "$q" | sed 's|BASE|"base":"a",|; s|IDS|"x-v1","z-v1"|; s|"a":{"description":"d",|"a":{"description":"d","base":"b",|')"
for _e in base-missing-id base-cycle base-self base-unknown; do
  grep -q base "$d/err-profiles-$_e" || bad "profiles-$_e: the refusal does not mention base: $(cat "$d/err-profiles-$_e")"
done
mkdir -p "$d/in-profile-ok"
printf '%s\n' "$(sub "$r,$r2,$r3")" > "$d/in-profile-ok/recipes.json"
printf '%s\n' "$(printf '%s' "$q" | sed 's|BASE|"base":"a",|; s|IDS|"x-v1","z-v1"|')" > "$d/in-profile-ok/profiles.json"
sh build/stage-sdk-metadata.sh "$d/in-profile-ok" "$d/out-profile-ok" 2>"$d/err-profile-ok" \
  || bad "a well-formed profile was refused: $(cat "$d/err-profile-ok")"

mkdir -p "$d/in-ok"
printf '%s\n' "$(sub "$r")" > "$d/in-ok/recipes.json"
sh build/stage-sdk-metadata.sh "$d/in-ok" "$d/out-ok" || bad "the well-formed control recipe set was refused: $(cat "$d/err-ok" 2>/dev/null)"

echo "== cmake_without_shipyard (a Linux runner)"
mkdir -p "$d/bin"
[ -x "$RC" ] || bad "no real cmake for the stand-in"
printf '#!/bin/sh\n: > "%s/used-cmake"\nexec "%s" "$@"\n' "$d" "$RC" > "$d/bin/cmake"
chmod +x "$d/bin/cmake"
PATH="$d/bin:/usr/bin:/bin" sh build/stage-sdk-metadata.sh sdk-metadata "$d/staged-linux" \
  || bad "the stager failed with only cmake on PATH"
[ -f "$d/used-cmake" ] || bad "with no shipyard-cmake on PATH, the stager did not use the cmake on PATH"

[ "$fail" -eq 0 ] && echo "sdk-metadata OK"
exit "$fail"
