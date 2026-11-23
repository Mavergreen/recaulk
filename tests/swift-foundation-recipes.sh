#!/bin/sh
# platform: host-agnostic -- python3 only; the fixture SDK is in tests/fixtures/swift-foundation/gen.
# spec: .superpowers/specs/2026-11-23-swift-foundation-recipes-design.md -- one combined recipe per header holding
#       the header's latest recipe's replacements plus the facts; a released recipe is chained, an unreleased
#       generated one rewritten in place; replacements unique and non-overlapping in the pristine header.
set -eu
cd "$(dirname "$0")/.."
G=tests/fixtures/swift-foundation/gen
d="$(mktemp -d "${TMPDIR:-/tmp}/swift-foundation-recipes.XXXXXX")"
trap 'rm -rf "$d"' EXIT
gen() {  # gen DIR FACTS RELEASED [RECIPES-SEED]
  [ -f "$1/recipes.json" ] || cp "${4:-$G/recipes.json}" "$1/recipes.json"
  mkdir -p "$1/probes"
  python3 build/gen-swift-foundation-recipes.py --sdk "$G/sdk" --facts "$2" --hand "$G/hand.json" \
    --recipes "$1/recipes.json" --released "$3" --probes "$1/probes" --profiles "$1/profiles.json"
}
mkdir -p "$d/a" "$d/b" "$d/c"
gen "$d/a" "$G/facts.json" "$G/recipes.json"
cp -R "$d/a" "$d/a2"; gen "$d/a2" "$G/facts.json" "$G/recipes.json"
diff -r "$d/a" "$d/a2" >/dev/null || { echo "FAIL: idempotent: a second run changed something"; exit 1; }
cp -R "$d/a/." "$d/b"; gen "$d/b" "$G/facts-no-title.json" "$G/recipes.json"
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
assert t.count('@property (readonly, copy) NSString *name;') == 1 and t.count('- (NSString *)name;') == 1, t  # repeated decl placed
assert t.index('@property (readonly, copy) NSString *name;') > t.index('@interface NSOther'), t
assert 'typedef NS_ENUM(NSUInteger, NSThingEdge)' in t and 'NSThingEdgeMin = 0 };\n@interface' in t, t  # superseded base
assert 'enum { NSThingEdgeMin = 0 };' not in t, t
assert t.index('typedef NSString *NSOtherKey') < t.index('@interface NSOther'), t
assert '@property (readonly, copy) NSString *label;' in materialize(a['foundation-new-v1'])
assert a['foundation-new-v1']['aliases'] == ['System/Library/Frameworks/Foundation.framework/Headers/NSNew.h']
p = json.load(open(os.path.join(d, 'a', 'profiles.json')))
ids = p['profiles']['swift-foundation']['recipes']
assert ids == ['foundation-new-v1', 'foundation-thing-v2'], ids
hs = [a[i]['header'] for i in ids]; assert len(hs) == len(set(hs))                                    # one_per_header
probe = open(os.path.join(d, 'a', 'probes', 'foundation-thing-v2.m')).read()
assert '// needs: foundation-new-v1' in probe and '// ast: ' in probe, probe
b = load('b')                                                                                         # rewrite_unreleased_in_place
assert set(b) == set(a), sorted(b)
assert '@property (readonly, copy) NSString *title;' not in materialize(b['foundation-thing-v2'])
c = load('c')                                                                                         # fold_hand_vnext
assert 'foundation-thing-v4' in c, sorted(c)
assert '- (NSString *)extra2;' in materialize(c['foundation-thing-v4'])
PY
echo "swift-foundation-recipes OK"
