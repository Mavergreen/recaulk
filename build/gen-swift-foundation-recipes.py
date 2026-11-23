#!/usr/bin/env python3
# platform: host-agnostic -- python3 and the pinned 10.9 SDK only.
# spec: .superpowers/specs/2026-11-23-swift-foundation-recipes-design.md -- for every header the facts touch, one
#       combined recipe: the header's latest recipe's replacements plus the facts. A released recipe is chained
#       (-vN+1); one this generator made and no release has shipped is rewritten in place. The profile names
#       every such recipe, at most one per header. Replacements are unique and non-overlapping in the pristine
#       header, as shipyard's materializer requires.
# usage: gen-swift-foundation-recipes.py --sdk SDK109 --facts F --hand H --recipes R --released RELEASED_R
#          --probes DIR --profiles P
import argparse, hashlib, json, os, re, sys

PROFILE = 'swift-foundation'
DESCRIPTION = "Foundation as swift-5.4's Foundation overlay needs it on 10.9"
VID = re.compile(r'^(.*)-v(\d+)$')
METHOD = re.compile(r'^[-+]\s*\(([^()]*)\)\s*(\w+)((?:\s+\w+\([^()]*\))*)\s*;$')


def retyped(prop, name, method):
    """The property with the type a base recipe gave its getter (generics' ObjectType), or None."""
    p = re.match(r'^(@property (?:\([^)]*\) )?)(.*?)\s*\*?\s*\b%s\b(.*);$' % re.escape(name), prop)
    m = METHOD.match(method.strip())
    if not p or not m:
        return None
    typ = m.group(1).strip()
    return '%s%s%s%s%s;' % (p.group(1), typ, '' if typ.endswith('*') else ' ', name, p.group(3))


def fail(msg):
    sys.exit('gen-swift-foundation-recipes: ' + msg)


def version(rid):
    m = VID.match(rid)
    if not m:
        fail('recipe id %s has no -vN' % rid)
    return m.group(1), int(m.group(2))


def default_stem(header):
    base = os.path.basename(header)[:-2]
    if '/Foundation.framework/' in header:
        return 'foundation-' + re.sub(r'^NS', '', base).lower()
    if '/CoreFoundation.framework/' in header:
        return 'corefoundation-' + re.sub(r'^CF', '', base).lower()
    if header.startswith('usr/include/objc/'):
        return 'objc-' + base.lower()
    fail('no recipe name for %s' % header)


def alias(header):
    m = re.match(r'^(System/Library/Frameworks/\w+\.framework)/Versions/\w+/Headers/(.*)$', header)
    return ['%s/Headers/%s' % (m.group(1), m.group(2))] if m else []


def umbrella(header):
    m = re.match(r'^System/Library/Frameworks/(\w+)\.framework/', header)
    if m:
        return '%s/%s.h' % (m.group(1), m.group(1))
    return header[len('usr/include/'):]


def fact_edits(facts, base_props):
    """(start, end, new, check) per fact; a property a base recipe already declares drops the method instead."""
    out = []
    for e in facts:
        if e['kind'] == 'property':
            name = e['name']
            new = '' if name in base_props else e['property']
            out.append([e['offset'], e['offset'] + len(e['decl']), new,
                        (e['category'] or e['class'], 'ObjCPropertyDecl .* %s \'' % name) if new else None, 'property', name])
            if e['setter_decl'] and new:
                out.append([e['setter_offset'], e['setter_offset'] + len(e['setter_decl']), '', None, 'setter'])
        elif e['kind'] == 'insert':
            m = re.search(r'typedef NSString \*(\w+) NS_EXTENSIBLE_STRING_ENUM;', e['text'])
            out.append([e['offset'], e['offset'], e['text'],
                        (m.group(1), 'TypedefDecl .* %s \'NSString \\*\'' % m.group(1)) if m else None, 'insert'])
        elif e['kind'] == 'replace':
            n, check = e['new'], None
            m = re.search(r'\b(\w+) const (\w+)', n)
            c = re.search(r'struct CF_BRIDGED(?:_MUTABLE)?_TYPE\(\w+\) (__\w+) \*', n)
            s = re.search(r'typedef (?:NS_ENUM|NS_OPTIONS|OBJC_ENUM)\(\w+, (\w+)\)', n)
            if c:
                check = (c.group(1), 'ObjCBridge(Mutable)?Attr')
            elif s:
                check = (s.group(1), 'EnumDecl .* %s' % s.group(1))
            elif m and m.group(1) != 'NSString' and 'NSString' in e['old']:
                check = (m.group(2), 'VarDecl .* %s \'const %s\'' % (m.group(2), m.group(1)))
            out.append([e['offset'], e['offset'] + len(e['old']), n, check, 'replace'])
        else:
            fail('unknown fact kind %r' % e['kind'])
    return out


def combine(text, base, facts, header):
    """Merge base replacements and fact edits into non-overlapping (start, end, new) on the pristine text."""
    base_edits = []
    for r in base:
        if text.count(r['old']) != 1:
            fail('%s: base replacement old is not unique: %r' % (header, r['old'][:80]))
        s = text.index(r['old'])
        base_edits.append([s, s + len(r['old']), r['new']])
    kept = []
    for b in base_edits:
        absorbed = False
        for f in facts:
            if f[0] == f[1]:
                if b[0] < f[0] < b[1]:
                    fail('%s: an insert falls inside a base replacement at %d' % (header, f[0]))
                continue
            if f[0] <= b[0] and b[1] <= f[1] and (f[0], f[1]) != (b[0], b[1]):
                absorbed = True        # a fact replacing more than the base edit supersedes it
                break
            if b[0] <= f[0] and f[1] <= b[1]:
                piece = text[f[0]:f[1]]
                if (f[0], f[1]) == (b[0], b[1]) and f[4] == 'property' and f[2] and retyped(f[2], f[5], b[2]):
                    b[2] = retyped(f[2], f[5], b[2])
                    f[2] = None
                    continue
                if b[2].count(piece) != 1:
                    fail('%s: cannot place a fact inside base replacement %r' % (header, b[2][:80]))
                b[2] = b[2].replace(piece, f[2], 1)
                f[2] = None            # applied through the base edit
            elif f[0] < b[1] and b[0] < f[1]:
                fail('%s: a fact partly overlaps a base replacement at %d' % (header, b[0]))
        if not absorbed:
            kept.append(b)
    edits = kept + [[f[0], f[1], f[2]] for f in facts if f[2] is not None]
    edits.sort(key=lambda x: (x[0], x[1] != x[0]))
    for x, y in zip(edits, edits[1:]):
        if y[0] < x[1]:
            fail('%s: two edits overlap at %d' % (header, y[0]))
    return edits


def widen(text, edits):
    """Group edits into replacements whose old is non-empty, unique and non-overlapping."""
    groups = []
    for s, e, n in edits:
        groups.append([s, e, [(s, e, n)]])

    def line_start(i):
        return text.rfind('\n', 0, i) + 1

    def line_end(i):
        j = text.find('\n', i)
        return len(text) if j < 0 else j + 1

    def compose(g):
        new, at = '', g[0]
        for ps, pe, pn in sorted(g[2], key=lambda p: (p[0], p[1] != p[0])):
            new += text[at:ps] + pn
            at = max(at, pe)
        return new + text[at:g[1]]

    changed = True
    while changed:
        changed = False
        out = []
        for g in groups:
            if out and g[0] < out[-1][1] or (out and g[0] == out[-1][1] and g[0] == g[1]):
                out[-1][1] = max(out[-1][1], g[1])
                out[-1][2] += g[2]
                changed = True
                continue
            out.append(g)
        groups = out
        for i, g in enumerate(groups):
            old = text[g[0]:g[1]]
            # platform: shipyard's materializer refuses an empty new, so a removal takes its line's newline too
            if old and text.count(old) == 1 and compose(g) not in ('', old):
                continue
            ns, ne = line_start(g[0]), max(line_end(g[1]) if g[1] > g[0] else line_end(g[0]), g[1])
            if (ns, ne) == (g[0], g[1]):
                ns = line_start(max(ns - 1, 0))
                if ns == g[0] and ne == len(text):
                    fail('cannot make an old unique at %d' % g[0])
                if ns == g[0]:
                    ne = line_end(ne)
            g[0], g[1] = ns, ne
            changed = True
    return [{'old': text[g[0]:g[1]], 'new': compose(g)} for g in groups]


def main():
    ap = argparse.ArgumentParser()
    for a in ('sdk', 'facts', 'hand', 'recipes', 'released', 'probes', 'profiles'):
        ap.add_argument('--' + a, required=True)
    o = ap.parse_args()
    facts = json.load(open(o.facts))['headers']
    hand = json.load(open(o.hand))
    data = json.load(open(o.recipes))
    recipes = data['recipes']
    released = {r['id'] for r in json.load(open(o.released))['recipes']}
    previous = set()
    if os.path.exists(o.profiles):
        previous = set(json.load(open(o.profiles))['profiles'].get(PROFILE, {}).get('recipes', []))
    by_id = {r['id']: r for r in recipes}

    made = {}
    for header in sorted(facts):
        on = [r for r in recipes if r['header'] == header]
        mine = [r for r in on if r['id'] in previous]
        if len(mine) > 1:
            fail('%s: the profile names %s' % (header, ', '.join(r['id'] for r in mine)))
        bases = [r for r in on if r['id'] not in previous]
        base = None
        if bases:
            top = max(version(r['id'])[1] for r in bases)
            tops = [r for r in bases if version(r['id'])[1] == top]
            if len(tops) != 1:
                fail('%s: %s tie as its latest recipe' % (header, ', '.join(r['id'] for r in tops)))
            base = tops[0]
        raw = open(os.path.join(o.sdk, header), 'rb').read()
        text = raw.decode('latin-1')
        base_reps = base['replacements'] if base else []
        base_props = set(m.group(1) for r in base_reps for m in re.finditer(r'@property[^;]*?[\s*](\w+)\s*(?:\w+\([^()]*\)\s*)*;', r['new']))
        fe = fact_edits(facts[header], base_props)
        checks = [f[3] for f in fe if f[3]]
        reps = widen(text, combine(text, base_reps, fe, header))
        prev = mine[0] if mine else None
        if prev and prev['replacements'] == reps:
            rid = prev['id']                     # unchanged: keep it, released or not
        elif prev and prev['id'] not in released:
            rid = prev['id']                     # unreleased: rewrite in place
        else:
            rid = '%s-v%d' % (default_stem(header), max([version(r['id'])[1] for r in on] or [0]) + 1)
            if rid in by_id:
                fail('%s would be %s, which exists' % (header, rid))
        recipe = {'id': rid, 'header': header, 'sha256': hashlib.sha256(raw).hexdigest(), 'aliases': alias(header),
                  'replacements': reps}
        made[rid] = (recipe, checks)

    ids = sorted(set(made) | set(hand.get('profile_extra', [])))
    # recipes keep their places; a recipe this run makes for the first time goes at the end
    out = [made[r['id']][0] if r['id'] in made else r for r in recipes]
    have = {r['id'] for r in recipes}
    out += [made[rid][0] for rid in sorted(made) if rid not in have]
    by_id = {r['id']: r for r in out}
    headers = [by_id[i]['header'] for i in ids]
    if len(headers) != len(set(headers)):
        fail('the profile names two recipes on one header')
    data['recipes'] = out
    with open(o.recipes, 'w') as f:
        f.write(json.dumps(data, indent=2) + '\n')

    for rid, (recipe, checks) in sorted(made.items()):
        if not checks:
            fail('%s: no fact gives its probe a check' % rid)
        kinds, picked = set(), []
        for c in checks:
            k = c[1].split(' ')[0]
            if k not in kinds:
                kinds.add(k)
                picked.append(c)
        for c in checks:
            if len(picked) >= 3:
                break
            if c not in picked:
                picked.append(c)
        lines = ['// Generated by build/gen-swift-foundation-recipes.py from sdk-metadata/swift-foundation-facts.json.',
                 '// needs: ' + ' '.join(i for i in ids if i != rid)]
        lines += ['// ast: %s %s' % c for c in picked[:3]]
        lines.append('#import <%s>' % umbrella(recipe['header']))
        with open(os.path.join(o.probes, rid + '.m'), 'w') as f:
            f.write('\n'.join(lines) + '\n')

    prof = {'schema': 1, 'profiles': {PROFILE: {'description': DESCRIPTION, 'recipes': ids}}}
    with open(o.profiles, 'w') as f:
        f.write(json.dumps(prof, indent=2) + '\n')


if __name__ == '__main__':
    main()
