#!/usr/bin/env python3
# platform: any host with clang22 and both SDKs; run by hand when the R1 facts change, output reviewed and committed.
# spec: .superpowers/specs/2026-11-23-swift-foundation-recipes-design.md -- R1: every zero-argument getter 10.9
#       declares, where the 11.3 SDK declares a property with that getter, becomes that property, keeping 10.9's
#       type text and trailing attributes and taking only 11.3's property attributes; never nullability.
# usage: extract-swift-foundation-facts.py --clang CLANG --old-sdk SDK109 --new-sdk SDK113 --import H [--import H...]
#          [--old-include DIR] [--new-include DIR] [--files REGEX] > facts.json
import argparse, json, os, re, subprocess, sys, tempfile

# spec: the design limits objc/NSObject.h to these members of the NSObject protocol.
ALLOW = {'usr/include/objc/NSObject.h': {'description', 'debugDescription', 'hash', 'superclass'},
         'usr/include/objc/runtime.h': set()}
HEAD = '/* Recaulk: declared from a later SDK so newer sources compile against 10.9. */\n'
# spec: R2's typedefs carry their own fallback, so a header's recipe does not depend on objcruntime-macros-v2.
FALLBACK = ('#ifndef NS_EXTENSIBLE_STRING_ENUM\n#if __has_attribute(swift_wrapper)\n'
            '#define NS_EXTENSIBLE_STRING_ENUM __attribute__((swift_wrapper(struct)))\n#else\n'
            '#define NS_EXTENSIBLE_STRING_ENUM\n#endif\n#endif\n')
NULLABILITY = re.compile(r'\s*\b(_Nullable|_Nonnull|_Null_unspecified|nullable|nonnull|null_unspecified)\b')
CF_TYPEDEF = re.compile(r'typedef (const )?struct (CF_BRIDGED(?:_MUTABLE)?_TYPE\(\w+\) )?(__\w+) \* (\w+);')


def typedef_text(name):
    return (HEAD + FALLBACK + '#ifndef __RECAULK_TYPEDEF_%s\n#define __RECAULK_TYPEDEF_%s 1\n'
            'typedef NSString *%s NS_EXTENSIBLE_STRING_ENUM;\n#endif\n' % (name, name, name))


def clean_type(t):
    return NULLABILITY.sub('', t).strip()
CONTAINERS = ('ObjCInterfaceDecl', 'ObjCCategoryDecl', 'ObjCProtocolDecl')


def ast(clang, sdk, includes, imports, minver):
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, 'tu.m')
        with open(src, 'w') as f:
            f.write(''.join('#import <%s>\n' % i for i in imports))
        cmd = [clang, '--no-default-config', '-fsyntax-only', '-x', 'objective-c', '-arch', 'x86_64',
               '-mmacosx-version-min=' + minver, '-isysroot', sdk, '-Xclang', '-ast-dump=json']
        for d in includes:
            cmd += ['-F', d, '-I', d]
        out = subprocess.run(cmd + [src], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if out.returncode != 0:
            sys.exit('extract: clang failed on %s:\n%s' % (sdk, out.stderr.decode()[:4000]))
        return json.loads(out.stdout)


class Walker:
    # platform: clang's JSON AST names a location's file only when it differs from the previously printed one,
    #   so the current file is carried through the dump in print order (loc, then range begin, then end).
    def __init__(self):
        self.file = None
        self.files = set()

    def _loc(self, loc):
        if not loc:
            return None
        if 'spellingLoc' in loc:
            self._loc(loc['spellingLoc'])
            return self._loc(loc['expansionLoc'])
        if 'file' in loc:
            self.file = loc['file']
            self.files.add(self.file)
        return (self.file, loc.get('offset'))

    def walk(self, node, visit, container=None):
        self._loc(node.get('loc'))
        r = node.get('range') or {}
        begin = self._loc(r.get('begin'))
        self._loc(r.get('end'))
        kind = node.get('kind')
        if kind in CONTAINERS:
            container = node
        visit(node, container, begin)
        for c in node.get('inner', []):
            self.walk(c, visit, container)


def owner(container):
    k = container['kind']
    if k == 'ObjCCategoryDecl':
        return container['interface']['name'], container.get('name') or None, 'category'
    if k == 'ObjCProtocolDecl':
        return container['name'], None, 'protocol'
    return container['name'], None, 'interface'


def relkey(path, roots):
    p = os.path.realpath(path)
    for r in roots:
        r = os.path.realpath(r)
        if p.startswith(r + os.sep):
            return os.path.relpath(p, r)
    return None


def getter(p):
    return (p.get('getter') or {}).get('name') or p['name']


def attrs(p, readonly, is_object):
    a = []
    if p.get('class'):
        a.append('class')
    if readonly:
        a.append('readonly')
    if p.get('nonatomic'):
        a.append('nonatomic')
    if is_object:
        if p.get('copy'):
            a.append('copy')
        elif p.get('strong') or p.get('retain'):
            a.append('strong')
        elif p.get('weak') or p.get('unsafe_unretained') or p.get('assign'):
            # platform: 10.9 consumers compile without ARC, where a weak property cannot be synthesized
            a.append('assign')
    if getter(p) != p['name']:
        a.append('getter=' + getter(p))
    return a


DECL = re.compile(r'^([-+])\s*\(([^()]*)\)\s*([A-Za-z_]\w*)\s*(.*?);$', re.S)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clang', required=True)
    ap.add_argument('--old-sdk', required=True)
    ap.add_argument('--new-sdk', required=True)
    ap.add_argument('--import', dest='imports', action='append', required=True)
    ap.add_argument('--old-include', action='append', default=[])
    ap.add_argument('--new-include', action='append', default=[])
    ap.add_argument('--files', default=r'Foundation\.framework/|^usr/include/objc/(NSObject|runtime)\.h$')
    ap.add_argument('--hand')
    o = ap.parse_args()
    files = re.compile(o.files)
    hand = json.load(open(o.hand)) if o.hand else {}
    string_enums = set(hand.get('string_enums', []))
    retypes = {(r['class'], r['selector']) for r in hand.get('retypes', [])}

    # 11.3: (owner, getter selector, is class) -> property node
    props, new_methods, new_vars = {}, {}, {}
    def vnew(n, c, _b):
        k = n.get('kind')
        if k == 'ObjCPropertyDecl' and c is not None:
            props.setdefault((owner(c)[0], getter(n), bool(n.get('class'))), n)
        elif k == 'ObjCMethodDecl' and c is not None:
            new_methods.setdefault((owner(c)[0], n['name']), n)
        elif k == 'VarDecl' and c is None:
            new_vars.setdefault(n['name'], clean_type(n['type']['qualType']).replace('const ', '').strip())
    wn = Walker()
    wn.walk(ast(o.clang, o.new_sdk, o.new_include, o.imports, '11.0'), vnew)

    # 10.9: methods per container
    methods, old_vars = [], {}
    def vold(n, c, b):
        if n.get('kind') == 'ObjCMethodDecl' and c is not None and not n.get('isImplicit'):
            methods.append((n, c, b))
        elif n.get('kind') == 'VarDecl' and c is None and b and b[0]:
            old_vars.setdefault(n['name'], b)
    wo = Walker()
    wo.walk(ast(o.clang, o.old_sdk, o.old_include, o.imports, '10.9'), vold)

    roots = [o.old_sdk] + o.old_include
    texts = {}
    def decl_text(path, off):
        if path not in texts:
            texts[path] = open(path, encoding='latin-1').read()  # platform: clang's offsets count bytes
        t = texts[path]
        return t[off:t.index(';', off) + 1]

    by_container = {}
    for n, c, b in methods:
        by_container.setdefault(id(c), {})[(n['name'], bool(n.get('instance')))] = (n, b)

    out = {}
    seen = set()
    for n, c, b in methods:
        sel = n['name']
        if ':' in sel or b is None or b[0] is None:
            continue
        key = relkey(b[0], roots)
        if key is None or not files.search(key):
            continue
        if key in ALLOW and sel not in ALLOW[key]:
            continue
        cls, cat, ckind = owner(c)
        is_class = not n.get('instance')
        p = props.get((cls, sel, is_class))
        if p is None:
            continue
        decl = decl_text(b[0], b[1])
        m = DECL.match(decl)
        if not m or m.group(3) != sel:
            continue
        typ, trailer = m.group(2).strip(), m.group(4).strip()
        if '^' in typ or '(' in typ:
            continue
        if (cls, sel) in retypes:
            typ = clean_type(p['type']['qualType'])
        if typ == 'instancetype':
            typ = cls + ' *'      # platform: a property cannot have type instancetype
        setter_decl = setter_offset = None
        readonly = bool(p.get('readonly'))
        if not readonly:
            sname = p.get('setter', {}).get('name') or 'set%s%s:' % (p['name'][0].upper(), p['name'][1:])
            s = by_container[id(c)].get((sname, not is_class))
            if s is None:
                readonly = True
            else:
                setter_decl, setter_offset = decl_text(b[0], s[1][1]), s[1][1]
        is_object = typ == 'id' or typ.startswith('id ') or typ.startswith('id<') or typ.endswith('*') \
            or typ in ('Class', 'instancetype')
        a = attrs(p, readonly, is_object)
        sep = '' if typ.endswith('*') else ' '
        prop = '@property %s%s%s%s%s;' % ('(%s) ' % ', '.join(a) if a else '', typ, sep, p['name'],
                                          ' ' + trailer if trailer else '')
        ident = (key, cls, cat, decl)
        if ident in seen:
            continue
        seen.add(ident)
        out.setdefault(key, []).append({'kind': 'property', 'name': p['name'], 'class': cls, 'container': ckind, 'category': cat,
                                        'decl': decl, 'offset': b[1], 'property': prop,
                                        'setter_decl': setter_decl, 'setter_offset': setter_offset})
    def add(key, e):
        out.setdefault(key, []).append(e)

    def text_of(key):
        for r in roots:
            f = os.path.join(r, key)
            if os.path.exists(f):
                if f not in texts:
                    texts[f] = open(f, encoding='latin-1').read()
                return texts[f]
        sys.exit('extract: no %s' % key)

    def unique(key, s):
        t = text_of(key)
        if t.count(s) != 1:
            sys.exit('extract: %r occurs %d times in %s' % (s[:80], t.count(s), key))
        return t.index(s)

    # R4 on methods that stay methods: 11.3's return type, without nullability
    for n, c, b in methods:
        cls = owner(c)[0]
        if (cls, n['name']) not in retypes or ':' not in n['name'] or b is None or b[0] is None:
            continue
        nm = new_methods.get((cls, n['name']))
        key = relkey(b[0], roots)
        if nm is None or key is None:
            continue
        old = decl_text(b[0], b[1])
        new = re.sub(r'^([-+]\s*\()[^()]*(\))', lambda m: m.group(1) + clean_type(nm['returnType']['qualType']) + m.group(2),
                     old, count=1)
        add(key, {'kind': 'replace', 'old': old, 'offset': b[1], 'new': new})

    # R2: constants 11.3 types as one of the string enums, retyped, with the typedef before the header's first one
    first = {}
    for name, typ in sorted(new_vars.items()):
        if typ not in string_enums or name not in old_vars:
            continue
        path, off = old_vars[name]
        key = relkey(path, roots)
        if key is None or not files.search(key):
            continue
        old = decl_text(path, off)
        new = re.sub(r'NSString\s*\*\s*const', typ + ' const', old, count=1)
        if new == old:
            continue
        add(key, {'kind': 'replace', 'old': old, 'offset': off, 'new': new})
        if (key, typ) not in first or off < first[(key, typ)]:
            first[(key, typ)] = off
    for (key, typ), off in sorted(first.items()):
        add(key, {'kind': 'insert', 'offset': off, 'text': typedef_text(typ)})
    for ti in hand.get('typedef_inserts', []):
        add(ti['header'], {'kind': 'insert', 'offset': unique(ti['header'], ti['before']), 'text': typedef_text(ti['typedef'])})

    # R3: every CF typedef 11.3 bridges, in the 10.9 headers this run covers
    bridged = {}
    for f in wn.files:
        if f.endswith('.h') and os.path.exists(f):
            for m in CF_TYPEDEF.finditer(open(f, encoding='latin-1').read()):
                if m.group(2):
                    bridged[(m.group(3), m.group(4))] = m.group(2)
    for f in sorted(wo.files):
        key = relkey(f, roots) if f.endswith('.h') else None
        if key is None or not files.search(key):
            continue
        t = text_of(key)
        for m in CF_TYPEDEF.finditer(t):
            if m.group(2) or (m.group(3), m.group(4)) not in bridged:
                continue
            new = 'typedef %sstruct %s%s * %s;' % (m.group(1) or '', bridged[(m.group(3), m.group(4))], m.group(3), m.group(4))
            add(key, {'kind': 'replace', 'old': m.group(0), 'offset': m.start(), 'new': new})

    # R5: an anonymous enum beside `typedef UNDER NAME;` becomes MACRO(UNDER, NAME) { cases }
    for es in hand.get('enum_shapes', []):
        key, name, macro = es['header'], es['typedef'], es['macro']
        t = text_of(key)
        td = list(re.finditer(r'typedef\s+(\w+)\s+%s\s*;' % re.escape(name), t))
        if len(td) != 1:
            sys.exit('extract: typedef %s occurs %d times in %s' % (name, len(td), key))
        td = td[0]
        gap = r'((?:\s|//[^\n]*\n|/\*.*?\*/)*)'
        before = list(re.finditer(r'enum\s*\{([^{}]*)\};' + gap + r'$', t[:td.start()], re.S))
        after = re.match(gap + r'enum\s*\{([^{}]*)\};', t[td.end():], re.S)
        if before:
            m = before[-1]
            start, end, body, between = m.start(), td.end(), m.group(1), m.group(2)
        elif after:
            start, end, body, between = td.start(), td.end() + after.end(), after.group(2), after.group(1)
        else:
            sys.exit('extract: no anonymous enum beside typedef %s in %s' % (name, key))
        between = between.strip()
        new = (between + '\n' if between else '') + 'typedef %s(%s, %s) {%s};' % (macro, td.group(1), name, body)
        add(key, {'kind': 'replace', 'old': t[start:end], 'offset': start, 'new': new})

    for r in hand.get('replaces', []):
        add(r['header'], {'kind': 'replace', 'old': r['old'], 'offset': unique(r['header'], r['old']), 'new': r['new']})
    for r in hand.get('inserts', []):
        add(r['header'], {'kind': 'insert', 'offset': unique(r['header'], r['before']), 'text': r['text']})

    for k in out:
        out[k].sort(key=lambda e: (e['offset'], e['kind'] != 'insert'))
    json.dump({'schema': 1, 'headers': {k: out[k] for k in sorted(out)}}, sys.stdout, indent=1)
    sys.stdout.write('\n')


if __name__ == '__main__':
    main()
