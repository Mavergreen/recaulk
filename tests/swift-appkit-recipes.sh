#!/bin/sh
# platform: host-agnostic -- python3 only; the fixture SDK is in tests/fixtures/swift-appkit/gen.
# spec: .superpowers/specs/2026-11-24-swift-appkit-recipes-design.md -- the generator takes its profile, keeps every
#       other profile, and makes swift-appkit a superset of swift-foundation; an AppKit header chains over its
#       latest recipe as appkit-<name>-vN+1, with the hand file's base_edits applied to that recipe first; a
#       base_edit that does not match exactly once, or two recipes on one header in the profile, fail.
set -eu
cd "$(dirname "$0")/.."
G=tests/fixtures/swift-appkit/gen
d="$(mktemp -d "${TMPDIR:-/tmp}/swift-appkit-recipes.XXXXXX")"
trap 'rm -rf "$d"' EXIT
gen() {  # gen DIR HAND PROFILES
  [ -f "$1/recipes.json" ] || cp "$G/recipes.json" "$1/recipes.json"
  [ -f "$1/profiles.json" ] || cp "$3" "$1/profiles.json"
  mkdir -p "$1/probes"
  python3 build/gen-swift-foundation-recipes.py --sdk "$G/sdk" --facts "$G/facts.json" --hand "$2" \
    --recipes "$1/recipes.json" --released "$G/recipes.json" --probes "$1/probes" --profiles "$1/profiles.json" \
    --generated "$1/generated.json" --profile swift-appkit --description A --base-profile swift-foundation
}
mkdir -p "$d/a" "$d/m" "$d/c"
gen "$d/a" "$G/hand.json" "$G/profiles.json"
cp -R "$d/a" "$d/a2"; gen "$d/a2" "$G/hand.json" "$G/profiles.json"
diff -r "$d/a" "$d/a2" >/dev/null || { echo "FAIL: idempotent: a second run changed something"; exit 1; }
if gen "$d/m" "$G/hand-missing.json" "$G/profiles.json" 2>"$d/m.err"; then
  echo "FAIL: base_edit_missing: a base_edit that matches nothing was accepted"; exit 1
fi
grep -q 'matches 0 times' "$d/m.err" || { echo "FAIL: base_edit_missing: wrong message: $(cat "$d/m.err")"; exit 1; }
if gen "$d/c" "$G/hand.json" "$G/profiles-clash.json" 2>"$d/c.err"; then
  echo "FAIL: same_header_refused: the base profile's recipe on the same header was accepted"; exit 1
fi
grep -q 'two recipes on one header' "$d/c.err" || { echo "FAIL: same_header_refused: wrong message: $(cat "$d/c.err")"; exit 1; }
python3 - "$d/a" "$G" <<'PY'
import json, os, sys
d, G = sys.argv[1:]
p = json.load(open(os.path.join(d, 'profiles.json')))['profiles']
seed = json.load(open(os.path.join(G, 'profiles.json')))['profiles']
assert p['swift-foundation'] == seed['swift-foundation'], p                        # keeps_other_profiles
assert set(p['swift-appkit']['recipes']) >= set(p['swift-foundation']['recipes']), p  # superset
assert p['swift-appkit']['description'] == 'A', p
r = {x['id']: x for x in json.load(open(os.path.join(d, 'recipes.json')))['recipes']}
assert 'appkit-widget-v3' in r and 'appkit-widget-v3' in p['swift-appkit']['recipes'], sorted(r)   # appkit_chain
new = ''.join(x['new'] for x in r['appkit-widget-v3']['replacements'])
assert 'typedef NS_OPTIONS(NSUInteger, NSThingMask) { NSThingMaskA = 1 << 0 };' in new, new
assert 'typedef NSUInteger NSThingMask;' not in new, new
assert '@property (readonly, copy) NSString *title;' in new, new
assert r['appkit-widget-v2'] == json.load(open(os.path.join(G, 'recipes.json')))['recipes'][2]   # released stays
PY
echo "swift-appkit-recipes OK"
