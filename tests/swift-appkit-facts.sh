#!/bin/sh
# platform: macOS-only -- runs clang22 against the pinned 10.9 SDK and the family's macOS 11.3 SDK (sdk113), a
#   macOS product; as tests/swift-foundation-facts.sh.
# spec: .superpowers/specs/2026-11-24-swift-appkit-recipes-design.md -- the committed swift-appkit facts are what the
#       extractor makes from both SDKs and sdk-metadata/swift-appkit-hand.json (facts_current), every fact's offset
#       locates its 10.9 text, and every swift-appkit row of swift-gg's table has a fact or a base_edit (rows_covered).
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
d="$(mktemp -d "${TMPDIR:-/tmp}/swift-appkit-facts.XXXXXX")"
trap 'rm -rf "$d"' EXIT
# spec: the headers are swift-gg's swift-appkit rows' (sdk-metadata/swift-appkit-rows.tsv, its table as sent)
FILES="^System/Library/Frameworks/AppKit\\.framework/Versions/C/Headers/($(awk -F '\t' 'NR > 1 && $5 == "swift-appkit" { sub(/\.h$/, "", $1); print $1 }' sdk-metadata/swift-appkit-rows.tsv | sort -u | paste -sd '|' -))\\.h\$"
python3 build/extract-swift-foundation-facts.py --clang "$CLANG22" --old-sdk "$SDK" --new-sdk "$SDK113" \
  --import AppKit/AppKit.h --files "$FILES" --hand sdk-metadata/swift-appkit-hand.json >"$d/real.json"
cmp -s "$d/real.json" sdk-metadata/swift-appkit-facts.json \
  || { echo "FAIL: sdk-metadata/swift-appkit-facts.json is not what the extractor makes; rerun it"; exit 1; }
python3 - "$SDK" <<'PY'
import json, sys
sdk = sys.argv[1]
facts = json.load(open('sdk-metadata/swift-appkit-facts.json'))['headers']
hand = json.load(open('sdk-metadata/swift-appkit-hand.json'))
for k, es in facts.items():                                                                       # offsets_locate
    t = open('%s/%s' % (sdk, k), encoding='latin-1').read()
    for e in es:
        s = e.get('decl') or e.get('old')
        if s:
            assert t[e['offset']:e['offset'] + len(s)] == s, (k, e)
rows = [l.split('\t') for l in open('sdk-metadata/swift-appkit-rows.tsv').read().splitlines()[1:]]
missing = []
for header, kind, sym, _need, profile in rows:                                                    # rows_covered
    if profile != 'swift-appkit':
        continue
    name = sym.lstrip('-+').split(':')[0]
    if name.startswith('is') and kind == 'R1-property':
        name = name[2].lower() + name[3:]
    blob = ''.join(json.dumps(e) for k, es in facts.items() if k.endswith('/' + header) for e in es)
    blob += ''.join(json.dumps(e) for e in hand.get('base_edits', []) if e['header'].endswith('/' + header))
    if kind == 'R1-property':
        ok = any(e['kind'] == 'property' and e['name'] == name for k, es in facts.items() if k.endswith('/' + header) for e in es) \
            or ('@property' in blob and name in blob)
    else:
        ok = name in blob
    if not ok:
        missing.append('%s %s %s' % (header, kind, sym))
assert not missing, 'rows with no fact:\n  ' + '\n  '.join(missing)
PY
echo "swift-appkit-facts OK"
