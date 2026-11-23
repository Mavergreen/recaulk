#!/usr/bin/env python3
# platform: any host with clang22 and both SDKs; run by hand when the R1 facts change, output reviewed and committed.
# spec: .superpowers/specs/2026-11-23-swift-foundation-recipes-design.md -- R1: every zero-argument getter 10.9
#       declares, where the 11.3 SDK declares a property with that getter, becomes that property, keeping 10.9's
#       type text and trailing attributes and taking only 11.3's property attributes; never nullability.
# usage: extract-swift-foundation-facts.py --clang CLANG --old-sdk SDK109 --new-sdk SDK113 --import H [--import H...]
#          [--old-include DIR] [--new-include DIR] [--files REGEX] > facts.json
import argparse, json, os, re, subprocess, sys, tempfile

# spec: the design limits objc/NSObject.h to these members of the NSObject protocol.
ALLOW = {'usr/include/objc/NSObject.h': {'description', 'debugDescription', 'hash', 'superclass'}}
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

    def _loc(self, loc):
        if not loc:
            return None
        if 'spellingLoc' in loc:
            self._loc(loc['spellingLoc'])
            return self._loc(loc['expansionLoc'])
        if 'file' in loc:
            self.file = loc['file']
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
    ap.add_argument('--files', default=r'Foundation\.framework/|^usr/include/objc/NSObject\.h$')
    o = ap.parse_args()
    files = re.compile(o.files)

    # 11.3: (owner, getter selector, is class) -> property node
    props = {}
    def vnew(n, c, _b):
        if n.get('kind') == 'ObjCPropertyDecl' and c is not None:
            props.setdefault((owner(c)[0], getter(n), bool(n.get('class'))), n)
    Walker().walk(ast(o.clang, o.new_sdk, o.new_include, o.imports, '11.0'), vnew)

    # 10.9: methods per container
    methods = []
    def vold(n, c, b):
        if n.get('kind') == 'ObjCMethodDecl' and c is not None and not n.get('isImplicit'):
            methods.append((n, c, b))
    Walker().walk(ast(o.clang, o.old_sdk, o.old_include, o.imports, '10.9'), vold)

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
        out.setdefault(key, []).append({'kind': 'property', 'class': cls, 'container': ckind, 'category': cat,
                                        'decl': decl, 'offset': b[1], 'property': prop,
                                        'setter_decl': setter_decl, 'setter_offset': setter_offset})
    json.dump({'schema': 1, 'headers': {k: out[k] for k in sorted(out)}}, sys.stdout, indent=1)
    sys.stdout.write('\n')


if __name__ == '__main__':
    main()
