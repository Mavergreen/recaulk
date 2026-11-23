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
  --import Fixture/Fixture.h --old-include "$F/109" --new-include "$F/113" --files 'Fixture\.h$' --hand "$F/hand.json" >"$d/fx.json"
python3 - "$d/fx.json" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))['headers']
assert list(h) == ['Fixture.framework/Headers/Fixture.h'], list(h)
by = {(e['class'], e['decl']): e for e in h['Fixture.framework/Headers/Fixture.h'] if e['kind'] == 'property'}
def one(cls, decl, prop, setter=None, category=None):
    e = by.pop((cls, decl), None)
    assert e, 'no entry for %s %s' % (cls, decl)
    assert e['kind'] == 'property', e
    assert e['property'] == prop, (e['property'], prop)
    assert e['setter_decl'] == setter, (e['setter_decl'], setter)
    assert e['category'] == category, (e['category'], category)
    assert e['name'] == prop.rstrip(';').split()[-1].lstrip('*'), e
one('FXThing', '- (BOOL)isOpen;', '@property (readonly, getter=isOpen) BOOL open;')              # getter_name
one('FXThing', '+ (id)shared;', '@property (class, readonly, strong) id shared;')                # class_property
one('FXThing', '+ (instancetype)current;', '@property (class, readonly, strong) FXThing *current;')  # instancetype
one('FXThing', '- (NSString *)name;', '@property (copy) NSString *name;',
    setter='- (void)setName:(NSString *)name;')                                                  # readwrite_pair
one('FXThing', '- (NSString *)title;', '@property (readonly, copy) NSString *title;')            # setter_elsewhere
one('FXThing', '- (NSString *)label;', '@property (readonly, copy) NSString *label;',
    category='FXExtras')                                                                         # category_placement, nullability_stripped
one('FXThing', '- (NSArray *)names;', '@property (readonly, copy) NSArray<NSString *> *names;')    # merge_property_retype
one('FXThing', '- (NSString *)URL;', '@property (readonly, copy) NSString *URL;')
one('FXThing', '- (NSString *)summary;', '@property (readonly, copy, nonnull) NSString *summary;')  # nonnull_property
one('FXThing', '- (NSString *)tag;', '@property (copy) NSString *tag;',
    setter='- (void)setTag:(NSString *)tag;', category='FXMore')                                  # setter_other_container
assert not by, 'unexpected entries (absent_in_109, onlyOld): %r' % sorted(by)
t = open('tests/fixtures/swift-foundation/109/Fixture.framework/Headers/Fixture.h').read()
other = [e for e in h['Fixture.framework/Headers/Fixture.h'] if e['kind'] != 'property']
reps = {e['old']: e['new'] for e in other if e['kind'] == 'replace'}
ins = [e for e in other if e['kind'] == 'insert']
assert reps.pop('- (NSArray *)componentsOf:(NSString *)s;') == '- (NSArray<NSString *> *)componentsOf:(NSString *)s;'  # retype_method
assert reps.pop('- (id)valueFor:(NSString *)key;') == '- (id)valueFor:(FXKey)key;'                     # retype_parameters
assert reps.pop('- (NSString *)joined:(NSString *)sep;') == '- (nonnull NSString *)joined:(NSString *)sep;'  # nonnull_method
assert reps.pop('- (void)setTitle:(NSString *)title;') == '@property (copy) NSString *title;'          # readwrite_in_subclass
assert reps.pop('- (void)setURL:(NSString *)URL;') == '@property (copy) NSString *URL;'                # acronym_setter
assert reps.pop('FOUNDATION_EXPORT NSString * const FXPlainA;') == 'FOUNDATION_EXPORT FXPlain const FXPlainA;'
assert reps.pop('FOUNDATION_EXPORT NSString * const FXKeyC;') == 'FOUNDATION_EXPORT FXKey const FXKeyC;'  # availability_in_type
assert reps.pop('FOUNDATION_EXPORT NSString * const FXKeyA;') == 'FOUNDATION_EXPORT FXKey const FXKeyA;'          # string_enum
assert reps.pop('FOUNDATION_EXPORT NSString *const FXKeyB NS_AVAILABLE(10_6, 4_0);') == \
    'FOUNDATION_EXPORT FXKey const FXKeyB NS_AVAILABLE(10_6, 4_0);'
assert reps.pop('enum {\n    FXOptA = 1,\n    FXOptB = 2\n};\ntypedef NSUInteger FXOptions;') == \
    'typedef NS_OPTIONS(NSUInteger, FXOptions) {\n    FXOptA = 1,\n    FXOptB = 2\n};'                   # enum_shape
assert reps.pop('typedef const struct __FXRef * FXRef;') == \
    'typedef const struct CF_BRIDGED_TYPE(NSString) __FXRef * FXRef;'                                  # cf_bridge
assert not reps, reps
cf = [e for e in ins if '#ifndef CF_BRIDGED_TYPE' in e['text']]                                       # cf_fallback
assert len(cf) == 1 and t[cf[0]['offset']:].startswith('typedef const struct __FXRef * FXRef;'), cf
assert '#define CF_BRIDGED_MUTABLE_TYPE(T)\n' in cf[0]['text'], cf
ins = [e for e in ins if e not in cf]
assert len(ins) == 2, ins                                                                               # typedef inserts, one per anchor
assert any('typedef NSString *FXPlain;\n' in e['text'] for e in ins), ins                                # plain_string_enum
for e in ins:
    assert '#ifndef NS_EXTENSIBLE_STRING_ENUM' in e['text'] and 'nullable' not in e['text'], e
key = [e for e in ins if 'typedef NSString *FXKey NS_EXTENSIBLE_STRING_ENUM;' in e['text']][0]
assert t[key['offset']:].startswith('@class NSString, NSArray;'), key                                  # after the imports
assert '@class NSString;\n' in key['text'], key
oth = [e for e in ins if 'typedef NSString *FXOther NS_EXTENSIBLE_STRING_ENUM;' in e['text']][0]
assert t[oth['offset']:].startswith('@interface FXMutableThing : FXThing'), oth
for e in other:
    if e['kind'] == 'replace':
        assert t[e['offset']:e['offset'] + len(e['old'])] == e['old'], e
for e in h['Fixture.framework/Headers/Fixture.h']:                                               # offsets_locate
    if e['kind'] != 'property':
        continue
    assert t[e['offset']:e['offset'] + len(e['decl'])] == e['decl'], e
    if e['setter_decl']:
        assert t[e['setter_offset']:e['setter_offset'] + len(e['setter_decl'])] == e['setter_decl'], e
PY
# spec: README.md "Profiles" -- the committed facts are what the extractor makes from both SDKs and the hand
#       inputs (facts_current)
python3 build/extract-swift-foundation-facts.py --clang "$CLANG22" --old-sdk "$SDK" --new-sdk "$SDK113" \
  --import Foundation/Foundation.h --import objc/runtime.h --hand sdk-metadata/swift-foundation-hand.json >"$d/real.json"
cmp -s "$d/real.json" sdk-metadata/swift-foundation-facts.json \
  || { echo "FAIL: sdk-metadata/swift-foundation-facts.json is not what the extractor makes; rerun it"; exit 1; }
echo "swift-foundation-facts OK"
