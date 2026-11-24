#!/bin/sh
# platform: host-agnostic -- python3 only; the fixture SDK is in tests/fixtures/swift-foundation/gen.
# spec: .superpowers/specs/2026-11-23-swift-foundation-recipes-design.md -- one combined recipe per header holding
#       the header's latest recipe's replacements plus the facts; a released recipe is chained, an unreleased
#       generated one rewritten in place; replacements unique and non-overlapping in the pristine header.
set -eu
cd "$(dirname "$0")/.."
G=tests/fixtures/swift-foundation/gen
DESC="Foundation as swift-5.4's Foundation overlay needs it on 10.9"
d="$(mktemp -d "${TMPDIR:-/tmp}/swift-foundation-recipes.XXXXXX")"
trap 'rm -rf "$d"' EXIT
gen() {  # gen DIR FACTS RELEASED [RECIPES-SEED]
  [ -f "$1/recipes.json" ] || cp "${4:-$G/recipes.json}" "$1/recipes.json"
  mkdir -p "$1/probes"
  python3 build/gen-swift-foundation-recipes.py --sdk "$G/sdk" --facts "$2" --hand "$G/hand.json" \
    --recipes "$1/recipes.json" --released "$3" --probes "$1/probes" --profiles "$1/profiles.json" --generated "$1/generated.json" \
    --profile swift-foundation --description "$DESC"
}
mkdir -p "$d/a" "$d/b" "$d/c"
gen "$d/a" "$G/facts.json" "$G/recipes.json"
cp -R "$d/a" "$d/a2"; gen "$d/a2" "$G/facts.json" "$G/recipes.json"
diff -r "$d/a" "$d/a2" >/dev/null || { echo "FAIL: idempotent: a second run changed something"; exit 1; }
cp -R "$d/a/." "$d/b"; gen "$d/b" "$G/facts-no-title.json" "$G/recipes.json"
cp -R "$d/a" "$d/o"
python3 - "$d/o/recipes.json" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1]))
d['recipes'].append(dict(d['recipes'][0], id='foundation-other-v1', header='Other.h'))
open(sys.argv[1], 'w').write(json.dumps(d, indent=2) + '\n')
PY2
cp "$d/o/recipes.json" "$d/o-before.json"; gen "$d/o" "$G/facts.json" "$G/recipes.json"
cmp -s "$d/o-before.json" "$d/o/recipes.json" || { echo "FAIL: keeps_order: a recipe added after generation moved"; exit 1; }
cp -R "$d/a" "$d/r"; gen "$d/r" "$G/facts.json" "$d/a/recipes.json"
diff -r "$d/a" "$d/r" >/dev/null || { echo "FAIL: released_unchanged: regenerating released recipes from the same facts changed them"; exit 1; }
cp -R "$d/a" "$d/rc"; gen "$d/rc" "$G/facts-no-title.json" "$d/a/recipes.json"
cp -R "$d/rc" "$d/rc2"; gen "$d/rc2" "$G/facts-no-title.json" "$d/rc/recipes.json"
diff -r "$d/rc" "$d/rc2" >/dev/null || { echo "FAIL: chain_then_regenerate: a chained recipe changed when regenerated from the same facts"; exit 1; }
gen "$d/c" "$G/facts.json" "$G/recipes-hand-v3.json" "$G/recipes-hand-v3.json"
python3 - "$d" "$G" <<'PY'
import json, os, sys
d, G = sys.argv[1:]
H = 'System/Library/Frameworks/Foundation.framework/Versions/C/Headers/'
def load(x):
    return {r['id']: r for r in json.load(open(os.path.join(d, x, 'recipes.json')))['recipes']}
def materialize(r):
    t = open(os.path.join(G, 'sdk', r['header']), encoding='latin-1').read()
    spans = []
    for x in r['replacements']:
        assert x['old'] and t.count(x['old']) == 1, ('not unique', r['id'], x['old'])
        assert x['new'] and x['new'] != x['old'], ('empty or unchanged new', r['id'], x)
        s = t.index(x['old']); spans.append((s, s + len(x['old']), x['new']))
    spans.sort()
    for (a, b, _), (c, e, _) in zip(spans, spans[1:]):
        assert b <= c, ('overlap', r['id'])
    for s, e, n in reversed(spans):
        t = t[:s] + n + t[e:]
    return t
a = load('a')
assert set(a) == {'foundation-thing-v1', 'foundation-thing-v2', 'foundation-new-v1'}, sorted(a)      # chain_over_released, new_header_v1
t = materialize(a['foundation-thing-v2'])
assert t.count('BOOL fileURL;') == 1, t                                                              # overlap_with_existing
assert '- (BOOL)isFileURL;' not in t, t
assert '@property (readonly, copy) NSString *title;' in t
assert '@property (readonly, strong) ObjectType firstThing;' in t and '- (ObjectType)firstThing;' not in t, t  # property_takes_base_type
assert t.count('@property (readonly, copy) NSString *name;') == 1 and t.count('- (NSString *)name;') == 1, t  # repeated decl placed
assert t.index('@property (readonly, copy) NSString *name;') > t.index('@interface NSOther'), t
assert 'typedef NS_ENUM(NSUInteger, NSThingEdge)' in t and 'NSThingEdgeMin = 0 };\n@interface' in t, t  # superseded base
assert 'enum { NSThingEdgeMin = 0 };' not in t, t
assert t.index('typedef NSString *NSOtherKey') < t.index('@interface NSOther'), t
n = materialize(a['foundation-new-v1'])
assert '@property (copy) NSString *label;' in n and 'setLabel' not in n, n                        # setter_removed
assert a['foundation-new-v1']['aliases'] == ['System/Library/Frameworks/Foundation.framework/Headers/NSNew.h']
p = json.load(open(os.path.join(d, 'a', 'profiles.json')))
ids = p['profiles']['swift-foundation']['recipes']
assert ids == ['foundation-new-v1', 'foundation-thing-v2'], ids
hs = [a[i]['header'] for i in ids]; assert len(hs) == len(set(hs))                                    # one_per_header
probe = open(os.path.join(d, 'a', 'probes', 'foundation-thing-v2.m')).read()
assert '// needs: \n' in probe and '// ast: ' in probe, probe                                    # needs_only_support
b = load('b')                                                                                         # rewrite_unreleased_in_place
assert set(b) == set(a), sorted(b)
assert '@property (readonly, copy) NSString *title;' not in materialize(b['foundation-thing-v2'])
rc = load('rc')                                                                                       # released_changed chains
assert 'foundation-thing-v3' in rc and 'foundation-thing-v2' in rc, sorted(rc)
assert rc['foundation-thing-v2'] == a['foundation-thing-v2']
assert '@property (readonly, copy) NSString *title;' not in materialize(rc['foundation-thing-v3'])
assert rc['foundation-new-v1'] == a['foundation-new-v1']
c = load('c')                                                                                         # fold_hand_vnext
assert 'foundation-thing-v4' in c, sorted(c)
assert '- (NSString *)extra2;' in materialize(c['foundation-thing-v4'])
PY
# spec: README.md "Profiles" -- the committed recipes, probes and profile are what the generator makes from
#       the committed facts (recipes_current); with the committed recipes as the released set, a current tree regenerates unchanged
. build/msc.sh
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
mkdir -p "$d/real/probes"
cp sdk-metadata/recipes.json sdk-metadata/profiles.json "$d/real/"
cp sdk-metadata/swift-foundation-generated.json "$d/real/generated.json"
cp tests/fixtures/sdk-probes/*.m "$d/real/probes/"
python3 build/gen-swift-foundation-recipes.py --sdk "$SDK" --facts sdk-metadata/swift-foundation-facts.json \
  --hand sdk-metadata/swift-foundation-hand.json --recipes "$d/real/recipes.json" --released sdk-metadata/recipes.json \
  --probes "$d/real/probes" --profiles "$d/real/profiles.json" --generated "$d/real/generated.json" \
  --profile swift-foundation --description "$DESC"
cmp -s "$d/real/generated.json" sdk-metadata/swift-foundation-generated.json && cmp -s "$d/real/recipes.json" sdk-metadata/recipes.json && cmp -s "$d/real/profiles.json" sdk-metadata/profiles.json \
  && diff -r "$d/real/probes" tests/fixtures/sdk-probes >/dev/null \
  || { echo "FAIL: the committed recipes are not what build/gen-swift-foundation-recipes.py makes from the facts; regenerate"; exit 1; }
echo "swift-foundation-recipes OK"
