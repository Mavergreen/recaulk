#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
# platform: off macOS, shipyard's install action puts no shipyard-cmake on PATH; the runner's cmake serves
SC="$(command -v shipyard-cmake || command -v cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
[ -x "$SC" ] || { echo "FAIL: no shipyard-cmake or cmake"; exit 1; }

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
  extra="$(cd "$d/staged" && find . -type f ! -name recipes.json)"
  [ -z "$extra" ] || bad "staging copied more than recipes.json: $extra"
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
refuse replacement-extra-key "$(sub "$(printf '%s' "$r" | sed 's|"new":"b"|"new":"b","regex":true|')")"
mkdir -p "$d/in-ok"
printf '%s\n' "$(sub "$r")" > "$d/in-ok/recipes.json"
sh build/stage-sdk-metadata.sh "$d/in-ok" "$d/out-ok" || bad "the well-formed control recipe set was refused: $(cat "$d/err-ok" 2>/dev/null)"

echo "== cmake_without_shipyard (a Linux runner)"
mkdir -p "$d/bin"
printf '#!/bin/sh\n: > "%s/used-cmake"\nexec "%s" "$@"\n' "$d" "$SC" > "$d/bin/cmake"
chmod +x "$d/bin/cmake"
PATH="$d/bin:/usr/bin:/bin" sh build/stage-sdk-metadata.sh sdk-metadata "$d/staged-linux" \
  || bad "the stager failed with only cmake on PATH"
[ -f "$d/used-cmake" ] || bad "with no shipyard-cmake on PATH, the stager did not use the cmake on PATH"

[ "$fail" -eq 0 ] && echo "sdk-metadata OK"
exit "$fail"
