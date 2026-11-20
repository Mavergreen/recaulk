# platform: host-agnostic -- python 2.7 (10.9) and python 3 (Linux, modern Mac) alike
# usage: plist.py FILE get KEY[.KEY...]   prints the value (a dict prints its keys, one per line); exit 2 if absent
#        plist.py FILE keys                prints the top-level keys
import plistlib, sys
path, op = sys.argv[1], sys.argv[2]
with open(path, 'rb') as f:
    d = plistlib.load(f) if hasattr(plistlib, 'load') else plistlib.readPlist(f)
if op == 'keys':
    for k in sorted(d): print(k)
    sys.exit(0)
v = d
for part in sys.argv[3].split('.'):
    if not isinstance(v, dict) or part not in v: sys.exit(2)
    v = v[part]
if isinstance(v, dict):
    for k in sorted(v): print('%s=%s' % (k, v[k]))
else:
    print(v)
