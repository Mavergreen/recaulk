#!/bin/sh
# platform: host-agnostic -- reads librecaulk.a with llvm-nm; libRecaulkSystem.dylib compiles the same source
# spec: README.md "Dispatch on 10.9" -- the inactive attribute makes no class and touches no object's indexed ivars:
#       Drydock's strict guard cannot model a class made at run time, and refuses class_createInstance,
#       object_getIndexedIvars and object_dispose as unclassified, so a strict-guarded product that called
#       dispatch_queue_create failed it (fuse-gg's MFMount, libfuse 2 and macFUSE.framework, Recaulk 20261121.1-.6)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
d="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-inactive-imports.XXXXXX")"
trap 'rm -rf "$d"' EXIT
banned='_objc_allocateClassPair _objc_registerClassPair _objc_duplicateClass _class_createInstance _object_getIndexedIvars _object_dispose _class_addIvar _class_addMethod'
"$NM" -u -A "$T/lib/librecaulk.a" > "$d/a" || { echo "FAIL: $NM cannot read librecaulk.a"; exit 1; }
grep -q 'dispatch_inactive' "$d/a" || { echo "FAIL: librecaulk.a has no dispatch_inactive member, so this test reads nothing"; exit 1; }
for s in $banned; do
  hit="$(grep 'dispatch_inactive' "$d/a" | awk -v s="$s" '$NF == s { m = $1; sub(/:$/, "", m); sub(/^.*\.a:/, "", m); print m }' | head -1)"
  [ -z "$hit" ] || { echo "FAIL: librecaulk.a's $hit imports $s"; fail=1; }
done
[ "$fail" = 0 ] && echo "dispatch-inactive-imports OK"
exit $fail
