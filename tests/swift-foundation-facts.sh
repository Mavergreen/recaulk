#!/bin/sh
# platform: macOS-only -- runs clang22 against the pinned 10.9 SDK and the family's macOS 11.3 SDK (sdk113).
# spec: .superpowers/specs/2026-11-23-swift-foundation-recipes-design.md -- the R1 facts are 10.9's own getters
#       redeclared as the 11.3 SDK's properties, with 10.9's types and no nullability; this proves the extractor
#       on a fixture pair, then checks the committed facts file's hand entries against the pinned 10.9 SDK.
set -eu
cd "$(dirname "$0")/.."
. build/msc.sh
for c in /usr/local/mavergreen/clang22/bin/clang /usr/local/mavergreen/clang22-cross/bin/clang; do
  [ -x "$c" ] && CLANG22=$c && break
done
[ -n "${CLANG22:-}" ] || { echo "FAIL: no installed clang22"; exit 1; }
SDK113=${SDK113:-/usr/local/mavergreen/sdk113/SDKs/MacOSX11.3.sdk}
[ -d "$SDK113" ] || { echo "FAIL: no macOS 11.3 SDK at $SDK113 (install the sdk113 product)"; exit 1; }
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
d="$(mktemp -d "${TMPDIR:-/tmp}/swift-foundation-facts.XXXXXX")"
trap 'rm -rf "$d"' EXIT
F=tests/fixtures/swift-foundation
python3 build/extract-swift-foundation-facts.py --clang "$CLANG22" --old-sdk "$SDK" --new-sdk "$SDK113" \
  --import Fixture/Fixture.h --old-include "$F/109" --new-include "$F/113" --files 'Fixture\.h$' >"$d/fx.json"
python3 - "$d/fx.json" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))['headers']
assert list(h) == ['Fixture.framework/Headers/Fixture.h'], list(h)
by = {(e['class'], e['decl']): e for e in h['Fixture.framework/Headers/Fixture.h']}
def one(cls, decl, prop, setter=None, category=None):
    e = by.pop((cls, decl), None)
    assert e, 'no entry for %s %s' % (cls, decl)
    assert e['kind'] == 'property', e
    assert e['property'] == prop, (e['property'], prop)
    assert e['setter_decl'] == setter, (e['setter_decl'], setter)
    assert e['category'] == category, (e['category'], category)
one('FXThing', '- (BOOL)isOpen;', '@property (readonly, getter=isOpen) BOOL open;')              # getter_name
one('FXThing', '+ (id)shared;', '@property (class, readonly, strong) id shared;')                # class_property
one('FXThing', '- (NSString *)name;', '@property (copy) NSString *name;',
    setter='- (void)setName:(NSString *)name;')                                                  # readwrite_pair
one('FXThing', '- (NSString *)title;', '@property (readonly, copy) NSString *title;')            # setter_elsewhere
one('FXThing', '- (NSString *)label;', '@property (readonly, copy) NSString *label;',
    category='FXExtras')                                                                         # category_placement, nullability_stripped
assert not by, 'unexpected entries (absent_in_109, onlyOld): %r' % sorted(by)
t = open('tests/fixtures/swift-foundation/109/Fixture.framework/Headers/Fixture.h').read()
for e in h['Fixture.framework/Headers/Fixture.h']:                                               # offsets_locate
    assert t[e['offset']:e['offset'] + len(e['decl'])] == e['decl'], e
    if e['setter_decl']:
        assert t[e['setter_offset']:e['setter_offset'] + len(e['setter_decl'])] == e['setter_decl'], e
PY
echo "swift-foundation-facts OK"
