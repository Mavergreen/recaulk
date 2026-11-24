#!/bin/sh
# platform: host-agnostic -- python3 and the pinned 10.9 SDK; the fixture SDK is in tests/fixtures/swift-appkit/gen.
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
mkdir -p "$d/a" "$d/m" "$d/c" "$d/u"
gen "$d/a" "$G/hand.json" "$G/profiles.json"
cp -R "$d/a" "$d/a2"; gen "$d/a2" "$G/hand.json" "$G/profiles.json"
diff -r "$d/a" "$d/a2" >/dev/null || { echo "FAIL: idempotent: a second run changed something"; exit 1; }
if gen "$d/m" "$G/hand-missing.json" "$G/profiles.json" 2>"$d/m.err"; then
  echo "FAIL: base_edit_missing: a base_edit that matches nothing was accepted"; exit 1
fi
grep -q 'matches 0 times' "$d/m.err" || { echo "FAIL: base_edit_missing: wrong message: $(cat "$d/m.err")"; exit 1; }
if gen "$d/u" "$G/hand-unused.json" "$G/profiles.json" 2>"$d/u.err"; then
  echo "FAIL: base_edit_unused: a base_edit on a header with no facts was ignored"; exit 1
fi
grep -q 'has no facts' "$d/u.err" || { echo "FAIL: base_edit_unused: wrong message: $(cat "$d/u.err")"; exit 1; }
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
assert new.count('@property (getter=isOpen) BOOL open;') == 1 and 'setOpen' not in new, new   # base_already_converted
probe = open(os.path.join(d, 'probes', 'appkit-widget-v3.m')).read()
assert "// ast: NSWidget ObjCPropertyDecl .* title '" not in probe, probe            # ambiguous_check_skipped
assert "// ast: NSWidget ObjCPropertyDecl .* name '" in probe, probe
assert r['appkit-widget-v2'] == json.load(open(os.path.join(G, 'recipes.json')))['recipes'][2]   # released stays
PY
# spec: README.md "Profiles" -- the committed swift-foundation and swift-appkit recipes, probes and profiles are what
#       the generator makes from the committed facts, foundation first (recipes_current); swift-appkit carries all of
#       swift-foundation (superset), no NS_SWIFT_NAME (swift's apinotes name things), and a real tagged type for
#       every R5 row (r5_tagged)
. build/msc.sh
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
R="$d/real"; mkdir -p "$R/probes"
cp sdk-metadata/recipes.json sdk-metadata/profiles.json "$R/"
cp sdk-metadata/swift-foundation-generated.json "$R/fgen.json"; cp sdk-metadata/swift-appkit-generated.json "$R/agen.json"
cp tests/fixtures/sdk-probes/*.m "$R/probes/"
python3 build/gen-swift-foundation-recipes.py --sdk "$SDK" --facts sdk-metadata/swift-foundation-facts.json \
  --hand sdk-metadata/swift-foundation-hand.json --recipes "$R/recipes.json" --released sdk-metadata/recipes.json \
  --probes "$R/probes" --profiles "$R/profiles.json" --generated "$R/fgen.json" \
  --profile swift-foundation --description "Foundation as swift-5.4's Foundation overlay needs it on 10.9"
python3 build/gen-swift-foundation-recipes.py --sdk "$SDK" --facts sdk-metadata/swift-appkit-facts.json \
  --hand sdk-metadata/swift-appkit-hand.json --recipes "$R/recipes.json" --released sdk-metadata/recipes.json \
  --probes "$R/probes" --profiles "$R/profiles.json" --generated "$R/agen.json" \
  --profile swift-appkit --description "AppKit and Foundation as swift-5.4's AppKit overlay needs them on 10.9" \
  --base-profile swift-foundation
cmp -s "$R/recipes.json" sdk-metadata/recipes.json && cmp -s "$R/profiles.json" sdk-metadata/profiles.json \
  && cmp -s "$R/fgen.json" sdk-metadata/swift-foundation-generated.json && cmp -s "$R/agen.json" sdk-metadata/swift-appkit-generated.json \
  && diff -r "$R/probes" tests/fixtures/sdk-probes >/dev/null \
  || { echo "FAIL: recipes_current: the committed recipes are not what the generator makes from the facts; regenerate"; exit 1; }
python3 - "$SDK" <<'PY'
import json, sys
sdk = sys.argv[1]
p = json.load(open('sdk-metadata/profiles.json'))['profiles']
assert set(p['swift-appkit']['recipes']) >= set(p['swift-foundation']['recipes']), 'superset'
r = {x['id']: x for x in json.load(open('sdk-metadata/recipes.json'))['recipes']}
mine = [r[i] for i in p['swift-appkit']['recipes'] if '/AppKit.framework/' in r[i]['header']]
assert not [x['id'] for x in mine if any('NS_SWIFT_NAME' in y['new'] for y in x['replacements'])], 'no_swift_name'
def materialize(x):
    t = open('%s/%s' % (sdk, x['header']), encoding='latin-1').read()
    for y in x['replacements']:
        t = t.replace(y['old'], y['new'], 1)
    return t
text = {x['header'].split('/')[-1]: materialize(x) for x in mine}
want = {'NSEvent.h': 'NS_OPTIONS(NSUInteger, NSEventModifierFlags)', 'NSView.h': 'NS_OPTIONS(NSUInteger, NSAutoresizingMaskOptions)',
        'NSWindow.h': 'NS_OPTIONS(NSUInteger, NSWindowStyleMask)', 'NSTrackingArea.h': 'NS_OPTIONS(NSUInteger, NSTrackingAreaOptions)',
        'NSFontDescriptor.h': 'NS_OPTIONS(uint32_t, NSFontDescriptorSymbolicTraits)', 'NSText.h': 'NS_ENUM(NSUInteger, NSTextAlignment)',
        'NSGraphics.h': 'NS_ENUM(NSUInteger, NSCompositingOperation)', 'NSParagraphStyle.h': 'NS_ENUM(NSUInteger, NSLineBreakMode)'}
for h, s in want.items():                                                                          # r5_tagged
    assert s in text[h], (h, s)
for h, n in [('NSEvent.h', 'NSEventModifierFlags'), ('NSView.h', 'NSAutoresizingMaskOptions'), ('NSWindow.h', 'NSWindowStyleMask'),
             ('NSText.h', 'NSTextAlignment'), ('NSGraphics.h', 'NSCompositingOperation')]:
    assert 'typedef NSUInteger %s;' % n not in text[h], (h, n)
# spec: the formal-protocol row: 11.3 hides NSObject's controlTextDidChange: category from Swift 4.2+, so a Swift
#       NSTextFieldDelegate implements controlTextDidChange(_:) without override (category_hidden_from_swift)
assert '#if __swift__ < 40200\n@interface NSObject(NSControlSubclassNotifications)' in text['NSControl.h'], 'category_hidden_from_swift'
# spec: NSUserInterfaceItemIdentifier is a swift_wrapper struct; the table view's lookup takes it (identifier_typed)
assert '- (__kindof NSView *)makeViewWithIdentifier:(NSUserInterfaceItemIdentifier)identifier owner:(id)owner' in text['NSTableView.h'], 'identifier_typed'
# spec: swift-gg's measurement of 7e4683f, eight rows (gg_rows), and the maintainer's rulings on its two questions
#       (gg_rulings): usesSingleLineMode needs no availability, as librecaulk-objc.a provides it on 10.9, and
#       guarded later colors are declared at their availability
fnd = {x['header'].split('/')[-1]: materialize(x) for x in (r[i] for i in p['swift-appkit']['recipes'])
       if '/Foundation.framework/' in x['header']}
AV = lambda v: ' __attribute__((availability(macosx,introduced=%s)));' % v
for h, decl, label in [
        ('NSTableView.h', '- (NSTableColumn *)tableColumnWithIdentifier:(NSUserInterfaceItemIdentifier)identifier;', 'gg_rows 1'),
        ('NSTableColumn.h', '@property (copy) NSUserInterfaceItemIdentifier identifier;', 'gg_rows 2'),
        ('NSTableColumn.h', '- (instancetype)initWithIdentifier:(NSUserInterfaceItemIdentifier)identifier;', 'gg_rows 2'),
        ('NSTableColumn.h', '@property CGFloat width;', 'gg_rows 2'),
        ('NSTableColumn.h', '@property CGFloat minWidth;', 'gg_rows 2'),
        ('NSTableColumn.h', '@property CGFloat maxWidth;', 'gg_rows 2'),
        ('NSFontDescriptor.h', '- (id)objectForKey:(NSFontDescriptorAttributeName)anAttribute;', 'gg_rows 3'),
        ('NSResponder.h', '@property (strong) NSMenu *menu;', 'gg_rows 5'),
        ('NSWindow.h', '- (nonnull instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)aStyle '
                       'backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag;', 'gg_rows 6'),
        ('NSColor.h', '@property (class, readonly, strong) NSColor *separatorColor' + AV('10.14'), 'gg_rows 7'),
        ('NSControl.h', '- (nonnull instancetype)initWithFrame:(NSRect)frameRect;', 'gg_rows 8'),
        ('NSControl.h', '@property BOOL usesSingleLineMode;', 'gg_rulings'),
        ('NSColor.h', '@property (class, readonly, strong) NSColor *labelColor' + AV('10.10'), 'gg_rulings'),
        ('NSImageView.h', '@property (nullable, copy) NSColor *contentTintColor' + AV('10.14'), 'gg_rulings'),
        # spec: README.md "Objective-C methods" -- librecaulk-objc.a back-fills it on 10.9 (iterm_titlebar)
        ('NSWindow.h', '@property BOOL titlebarAppearsTransparent;', 'iterm_titlebar')]:
    assert decl in text.get(h, ''), (label, h, decl)
assert '+ (nonnull NSBundle *)bundleForClass:(Class)aClass;' in fnd['NSBundle.h'], 'gg_rows 4'
assert 'designated' not in text['NSWindow.h'].split('initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)')[1].split(';')[0].lower(), \
    'gg_rows 6: nonnull only, as measured'
for v in ('NSTrackingMouseEnteredAndExited', 'NSTrackingActiveAlways', 'NSTrackingEnabledDuringMouseDrag'):
    assert text['NSTrackingArea.h'].count(v) == 1, v
PY
echo "swift-appkit-recipes OK"
