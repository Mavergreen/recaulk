#!/bin/sh
# platform: host-agnostic
# spec: README.md "Materializing an SDK view" "Applying recipes" -- shipyard's module's
#       semantics and refusals, the reserved paths, and never a write into the SDK
set -eu
cd "$(dirname "$0")/.."
F="$PWD/tests/fixtures/materialize"
d="$(mktemp -d "${TMPDIR:-/tmp}/materialize-apply.XXXXXX")"
trap 'chmod -R u+w "$d" 2>/dev/null; rm -rf "$d"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
sh build/build-materialize.sh host "$d/rm"
sh "$F/make-sdk.sh" "$d"
SDK="$d/MacOSX10.9.sdk"
snap() { (cd "$SDK" && find . | sort && find . -type f | sort | xargs cat) | cksum; }
before="$(snap)"
run() { "$d/rm" --dry-run --sdk "$SDK" --out "$d/out" --recipes "${R:-$F/recipes.json}" --profiles "$F/profiles.json" "$@" \
          >"$d/stdout" 2>"$d/err" && rc=0 || rc=$?; }
# spec: README.md "Materializing an SDK view" -- a refusal exits 1 with one stderr line naming what is at fault
refuse() {
  what="$1"; shift
  [ "$rc" = 1 ] || { bad "$what: exited $rc, want 1 ($(cat "$d/err"))"; return; }
  [ "$(wc -l <"$d/err" | tr -d ' ')" = 1 ] || bad "$what: more than one stderr line"
  for w in "$@"; do grep -qF -- "$w" "$d/err" || bad "$what: stderr lacks '$w': $(cat "$d/err")"; done
}
variant() { sed "$1" "$F/recipes.json" > "$d/v.json"; R="$d/v.json"; }

echo "== happy_path"
R= run --profile t
[ "$rc" = 0 ] || bad "the fixture profile exited $rc: $(cat "$d/err")"
awk '/^== System\/Library\/Frameworks\/Foundation.framework\/Versions\/C\/Headers\/NSArray.h$/{on=1;next} /^== /{on=0} on' \
  "$d/stdout" > "$d/nsarray"
cmp -s "$d/nsarray" "$F/NSArray.expected.h" || bad "NSArray.h was not rewritten to NSArray.expected.h"
grep -qxF 'int t_stdio_rewritten; /* "q" \\ */' "$d/stdout" || bad "stdio.h's escaped new text did not land decoded"

echo "== one_recipe"
R= run --recipe t-stdio-v1
[ "$rc" = 0 ] && ! grep -q NSArray "$d/stdout" || bad "--recipe t-stdio-v1 did more than stdio.h"

echo "== sha_mismatch"
printf ' ' >> "$SDK/usr/include/stdio.h"; R= run --profile t
refuse sha_mismatch SHA-256 usr/include/stdio.h t-stdio-v1
sh "$F/make-sdk.sh" "$d/fresh" && cp "$d/fresh/MacOSX10.9.sdk/usr/include/stdio.h" "$SDK/usr/include/stdio.h"

echo "== old_absent"
variant 's/int t_stdio_unrewritten;/int t_nowhere;/'; run --profile t
refuse old_absent t-stdio-v1 'does not occur'

echo "== old_twice"
printf 'int t_stdio_unrewritten;\nint t_stdio_unrewritten;\n' > "$d/twice.h"
cp "$d/twice.h" "$SDK/usr/include/stdio.h"
sum="$(openssl dgst -sha256 "$d/twice.h" | sed 's/.*= *//')"
variant "/usr\\/include\\/stdio.h/{n;s/[0-9a-f]\\{64\\}/$sum/;}"; run --profile t
refuse old_twice t-stdio-v1 'more than once'
cp "$d/fresh/MacOSX10.9.sdk/usr/include/stdio.h" "$SDK/usr/include/stdio.h"

echo "== new_empty"
variant 's|"new": "int t_stdio_rewritten.*"$|"new": ""|'; run --profile t
refuse new_empty t-stdio-v1 empty

echo "== new_is_old"
variant 's|"new": "int t_stdio_rewritten.*"$|"new": "int t_stdio_unrewritten;"|'; run --profile t
refuse new_is_old t-stdio-v1 'changes nothing'

echo "== alias_elsewhere"
variant 's|"System/Library/Frameworks/Foundation.framework/Headers/NSArray.h"|"usr/include/stdio.h"|'; run --profile t
refuse alias_elsewhere alias usr/include/stdio.h NSArray.h

echo "== two_recipes_one_header"
variant 's|"id": "t-stdio-v1"|"id": "t-stdio-v1"|; s|"header": "usr/include/stdio.h"|"header": "System/Library/Frameworks/Foundation.framework/Headers/NSArray.h"|'
run --profile t
refuse two_recipes_one_header t-array-v1 t-stdio-v1

echo "== unknown_ids"
R= run --recipe t-nope-v1; refuse unknown_recipe t-nope-v1
R= run --profile nope; refuse unknown_profile nope

echo "== layering"
sed 's|"profiles": {|"profiles": {"t-top": {"description": "over t", "base": "t", "recipes": ["t-array-v1"]},|' \
  "$F/profiles.json" > "$d/layered.json"
"$d/rm" --dry-run --sdk "$SDK" --out "$d/out" --recipes "$F/recipes.json" --profiles "$d/layered.json" --profile t-top \
  >/dev/null 2>"$d/err" && rc=0 || rc=$?
refuse base_missing_id "profile 't-top' lacks 't-stdio-v1' from its base 't'"
sed 's|"t-top": {"description": "over t", "base": "t", "recipes": \["t-array-v1"\]}|"t-top": {"description": "over t", "base": "t", "recipes": ["t-array-v1", "t-stdio-v1"]}|' \
  "$d/layered.json" > "$d/layered-ok.json"
"$d/rm" --dry-run --sdk "$SDK" --out "$d/out" --recipes "$F/recipes.json" --profiles "$d/layered-ok.json" --profile t-top \
  >/dev/null 2>"$d/err" || bad "a profile carrying its base's ids was refused: $(cat "$d/err")"
sed 's|"base": "t"|"base": "nope"|' "$d/layered.json" > "$d/layered-bad.json"
"$d/rm" --dry-run --sdk "$SDK" --out "$d/out" --recipes "$F/recipes.json" --profiles "$d/layered-bad.json" --profile t-top \
  >/dev/null 2>"$d/err" && rc=0 || rc=$?
refuse base_unknown "base 'nope' of 't-top' is not a profile"

echo "== reserved_paths"
mkdir -p "$SDK/usr/include/dispatch" "$SDK/usr/include/pthread"
cp "$SDK/usr/include/stdio.h" "$SDK/usr/include/dispatch/dispatch.h"
cp "$SDK/usr/include/stdio.h" "$SDK/usr/include/pthread/qos.h"
variant 's|"header": "usr/include/stdio.h"|"header": "usr/include/dispatch/dispatch.h"|'; run --recipe t-stdio-v1
refuse reserved_dispatch reserved usr/include/dispatch/dispatch.h
variant 's|"header": "usr/include/stdio.h"|"header": "usr/include/pthread/qos.h"|'; run --recipe t-stdio-v1
refuse reserved_qos reserved usr/include/pthread/qos.h
rm -rf "$SDK/usr/include/dispatch" "$SDK/usr/include/pthread"

echo "== not_a_plain_path"
variant 's|"header": "usr/include/stdio.h"|"header": "usr/include/../include/stdio.h"|'; run --recipe t-stdio-v1
refuse dotdot 'not a plain path' usr/include/../include/stdio.h

echo "== outside_the_sdk (RF1)"
mkdir -p "$d/elsewhere/Headers" && cp "$F/NSArray.h" "$d/elsewhere/Headers/NSArray.h"
fw="$SDK/System/Library/Frameworks/Foundation.framework/Versions/C"
mv "$fw/Headers" "$d/kept-headers" && ln -s "$d/elsewhere/Headers" "$fw/Headers"
before="$(snap)"
R= run --recipe t-array-v1
refuse outside_the_sdk 'outside the SDK' NSArray.h
rm "$fw/Headers" && mv "$d/kept-headers" "$fw/Headers"
before="$(snap)"

echo "== wrong_sdk_name"
ln -s "$SDK" "$d/Other.sdk"; mv "$SDK" "$d/MacOSX10.8.sdk"
"$d/rm" --dry-run --sdk "$d/MacOSX10.8.sdk" --out "$d/out" --recipes "$F/recipes.json" --profiles "$F/profiles.json" \
  --profile t >/dev/null 2>"$d/err" && rc=0 || rc=$?
refuse wrong_sdk_name MacOSX10.9.sdk MacOSX10.8.sdk
mv "$d/MacOSX10.8.sdk" "$SDK"; rm "$d/Other.sdk"

echo "== never_writes_the_sdk"
[ "$(snap)" = "$before" ] || bad "the SDK changed"
[ ! -e "$d/out" ] || bad "--dry-run wrote --out"
[ "$fail" = 0 ] && echo "materialize-apply OK"
exit "$fail"
