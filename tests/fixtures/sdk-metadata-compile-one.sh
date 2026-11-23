#!/bin/sh
# platform: macOS-only -- one recipe's probe for tests/sdk-metadata-compile.sh, which sets SC, MODULES, SDK,
#   CLANG22 and d; the report goes to $d/ID.out, and $d/ID.fail marks a failure.
# spec: README.md "SDK declaration metadata" -- see tests/sdk-metadata-compile.sh for what a probe proves.
set -u
id=$1
out="$d/$id.out"
: >"$out"
bad() { echo "FAIL: $*" >>"$out"; : >"$d/$id.fail"; }
probe="tests/fixtures/sdk-probes/$id.m"
[ -f "$probe" ] || { bad "$id has no probe $probe"; exit 0; }
need=$(sed -n 's|^// needs: ||p' "$probe")
sel=$(printf '%s;%s' "$id" "$need" | sed 's/;$//; s/ /;/g')
if ! ov=$("$SC" -DMODULES="$MODULES" -DSDK="$SDK" -DRECIPES="$PWD/sdk-metadata/recipes.json" -DIDS="$sel" \
            -DOUT="$d/$id" -P tests/fixtures/sdk-metadata-materialize.cmake 2>&1); then
  bad "$id does not materialize: $ov"; exit 0
fi
ov=$(printf '%s\n' "$ov" | tail -1)
flags="-fsyntax-only -Werror -x objective-c -fno-objc-arc -arch x86_64 -mmacosx-version-min=10.9 -isysroot $SDK"
# shellcheck disable=SC2086
"$CLANG22" $flags -ivfsoverlay "$ov" "$probe" >"$d/$id.with" 2>&1 \
  || { bad "$id: its probe does not compile through the overlay"; sed 's/^/    /' "$d/$id.with" | head -8 >>"$out"; }
# platform: clang22's default config puts Recaulk's own headers on the path, and they declare what
#   librecaulk.a back-fills (LSCopyDefaultApplicationURLForURL, say); a recipe edits the SDK, so it is
#   proved against the SDK alone: it must suffice there, and be needed there.
# shellcheck disable=SC2086
"$CLANG22" --no-default-config $flags -ivfsoverlay "$ov" "$probe" >"$d/$id.with-sdk" 2>&1 \
  || { bad "$id: its probe does not compile through the overlay on the SDK alone"; sed 's/^/    /' "$d/$id.with-sdk" | head -8 >>"$out"; }
asts=$(sed -n 's|^// ast: ||p' "$probe")
if [ -z "$asts" ]; then
  # shellcheck disable=SC2086
  "$CLANG22" --no-default-config $flags "$probe" >"$d/$id.without" 2>&1 \
    && bad "$id: its probe compiles on the SDK alone without the recipe (a no-op recipe)"
fi
# spec: an "// ast:" check holds through the overlay and not through its needs alone, so this recipe (not one
#       it needs) is what makes it hold
base=
if [ -n "$asts" ] && [ -n "$need" ]; then
  if ! bov=$("$SC" -DMODULES="$MODULES" -DSDK="$SDK" -DRECIPES="$PWD/sdk-metadata/recipes.json" \
               -DIDS="$(printf '%s' "$need" | sed 's/ /;/g')" -DOUT="$d/$id-needs" \
               -P tests/fixtures/sdk-metadata-materialize.cmake 2>&1); then
    bad "$id: its needs do not materialize: $bov"; exit 0
  fi
  base="-ivfsoverlay $(printf '%s\n' "$bov" | tail -1)"
fi
printf '%s\n' "$asts" | while read -r filter regex; do
  [ -n "$filter" ] || continue
  # shellcheck disable=SC2086
  "$CLANG22" --no-default-config $flags -ivfsoverlay "$ov" -Xclang -ast-dump -Xclang -ast-dump-filter="$filter" \
    "$probe" 2>/dev/null | grep -Eq -- "$regex" || bad "$id: $filter has no '$regex' through the overlay"
  # shellcheck disable=SC2086
  "$CLANG22" --no-default-config $flags $base -Xclang -ast-dump -Xclang -ast-dump-filter="$filter" \
    "$probe" 2>/dev/null | grep -Eq -- "$regex" && bad "$id: $filter has '$regex' without the recipe (a no-op recipe)"
done
weak=$(sed -n 's|^// weak: ||p' "$probe")
if [ -n "$weak" ]; then
  # shellcheck disable=SC2086
  "$CLANG22" $(printf '%s' "$flags" | sed 's/-fsyntax-only/-c/') -ivfsoverlay "$ov" -o "$d/$id.o" "$probe" >/dev/null 2>&1 \
    || { bad "$id: its probe does not compile to an object"; exit 0; }
  for sym in $weak; do
    "$(dirname "$CLANG22")/llvm-nm" -m "$d/$id.o" | awk -v s="$sym" '$1 == "(undefined)" && $2 == "weak" && $3 == "external" && $4 == s { f = 1 } END { exit !f }' \
      || bad "$id: $sym is not a weak reference, so the binary would not load on 10.9"
  done
fi
exit 0
