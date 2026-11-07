#!/bin/sh
# platform: host-agnostic -- reads and links x86_64 Mach-O with clang22's tools
# spec: README.md "Licences" -- every member built from an Apple-licensed source carries its APSL 2.0
#       section 2.3 notice as a local, no-dead-strip string, and share/recaulk/notices.tsv lists each one.
set -eu
LC_ALL=C
export LC_ALL
cd "$(dirname "$0")/.."
. tests/helpers/built.sh

tmp="$(mktemp -d "${TMPDIR:-/tmp}/apsl-notices.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
lib="$T/lib/librecaulk.a"
dylib="$T/lib/libRecaulkSystem.dylib"
tsv="$T/share/recaulk/notices.tsv"
set -- "$W"/macports-legacy-support-*
mpdir="$1"
mp="$mpdir/src"
[ -d "$mp" ] || { echo "FAIL: no MacPorts source under $W"; exit 1; }
digest="$(macports_pin DIGEST)"
apple='[Cc]opyright.*Apple|Apple Public Source|APPLE_LICENSE_HEADER'
allow=build/apsl-declaration-only.txt

marked() {
  _mk=0; grep -Eq "$apple" "$1" || _mk=$?
  [ "$_mk" -le 1 ] || { echo "FAIL: cannot read $1 (grep exit $_mk), so whether it is Apple-licensed is unknown"; exit 1; }
  return "$_mk"
}
# spec: README.md "Licences" -- a member's sources are everything the compiler reads for it but the SDK
#       and the compiler's own headers; a reviewed declaration-only Apple header counts only at its pinned bytes
apple_derived() {
  _ad_src="$1"; shift
  _ad_deps="$("$CC" $FLAGS -arch x86_64 -Os "$@" -M -MT x "$_ad_src")" \
    || { echo "FAIL: clang22 -M could not list what $_ad_src includes"; exit 1; }
  for _ad_d in $(printf '%s\n' "$_ad_deps" | tr '\\' ' '); do
    case "$_ad_d" in x:|"$SDK"/*|"$CL"/*) continue ;; esac
    marked "$_ad_d" || continue
    _ad_h="$(shasum -a 256 < "$_ad_d" | cut -c1-64)"
    awk -v p="${_ad_d#"$mpdir"/}" -v h="$_ad_h" '$1 == h && $2 == p { f = 1 } END { exit !f }' "$allow" && continue
    return 0
  done
  return 1
}

"$AR" t "$lib" | grep -v '^__\.SYMDEF' | sort > "$tmp/members"
: > "$tmp/expect"
while IFS= read -r m; do
  case "$m" in
    mp-*.o) src="$mp/${m#mp-}"; src="${src%.o}.c"; set -- -I"$mpdir/include" ;;
    recaulk-*.o) stem="${m#recaulk-}"; stem="${stem%.o}"; src="$MAVERICKS_ROOT/src/backfills/$stem.c"
      set -- -I"$W/own-include" -I"$MAVERICKS_ROOT/src" -I"$mpdir/include" ;;
    *) continue ;;
  esac
  [ -f "$src" ] || { bad "$m has no source at $src, so whether it is Apple-derived cannot be read"; continue; }
  if apple_derived "$src" "$@"; then echo "$m" >> "$tmp/expect"; fi
done < "$tmp/members"
[ -s "$tmp/expect" ] || bad "no member of $lib is built from an Apple-licensed source; MacPorts' atcalls.c and utimensat.c are"

mkdir "$tmp/x"
(cd "$tmp/x" && "$AR" x "$lib")
: > "$tmp/have"
for o in "$tmp"/x/*.o; do
  m="$(basename "$o")"
  if "$NM" "$o" 2>/dev/null | grep -q ' _recaulk_apsl_notice$'; then echo "$m" >> "$tmp/have"; fi
done
missing="$(comm -23 "$tmp/expect" "$tmp/have" | tr '\n' ' ')"
extra="$(comm -13 "$tmp/expect" "$tmp/have" | tr '\n' ' ')"
[ -z "$missing" ] || bad "members built from an Apple-licensed source carry no APSL notice: $missing"
[ -z "$extra" ] || bad "members carry an APSL notice though no source of theirs is Apple-licensed: $extra"

notice_of() { "$STRINGS" -a "$1" | grep "^Recaulk member " || :; }
while IFS= read -r m; do
  o="$tmp/x/$m"
  "$NM" "$o" | grep -q '^[0-9a-f]* s _recaulk_apsl_notice$' \
    || bad "$m's notice symbol is not a local data symbol: $("$NM" "$o" | grep apsl)"
  if "$NM" -g "$o" | grep -q apsl; then bad "$m's notice symbol is global"; fi
  s="$(notice_of "$o")"
  case "$s" in *"Recaulk member $m "*) ;; *) bad "$m's notice does not name the member: $s" ;; esac
  case "$s" in *"Apple Public Source License Version 2.0"*) ;; *) bad "$m's notice does not name APSL 2.0: $s" ;; esac
  case "$s" in *"https://github.com/macports/macports-legacy-support/blob/$digest/src/"*) ;;
    *) bad "$m's notice does not say where its source is, at the pinned commit $digest: $s" ;; esac
  case "$s" in *"https://github.com/Mavergreen/recaulk/releases"*) ;; *) bad "$m's notice does not name Recaulk's release source: $s" ;; esac
  printf '%s\t%s\n' "$m" "$s" >> "$tmp/embedded"
done < "$tmp/have"

[ -f "$tsv" ] || { bad "no $tsv"; echo "apsl-notices FAILED"; exit 1; }
grep -v '^#' "$tsv" | awk -F '\t' 'NF != 7 { print "FAIL: notices.tsv line " NR " has " NF " fields, not 7: " $0 }' | grep . && fail=1
for a in librecaulk.a libRecaulkSystem.dylib; do
  grep -v '^#' "$tsv" | awk -F '\t' -v a="$a" '$1 == a { print $2 "\t" $7 }' | sort > "$tmp/listed-$a"
  sort "$tmp/embedded" | cmp -s - "$tmp/listed-$a" \
    || bad "notices.tsv's $a rows are not exactly the notices the members carry: $(sort "$tmp/embedded" | diff - "$tmp/listed-$a" | head -5)"
done
grep -v '^#' "$tsv" | awk -F '\t' '$3 != "APSL-2.0" { print "FAIL: notices.tsv names licence " $3 " for " $2 }' | grep . && fail=1

"$NM" -gU "$lib" | grep apsl && bad "librecaulk.a exports a notice symbol"
"$NM" -gU "$dylib" | grep apsl && bad "libRecaulkSystem.dylib exports a notice symbol"
"$STRINGS" -a "$dylib" | grep '^Recaulk member ' | sort > "$tmp/in-dylib"
cut -f2 "$tmp/embedded" | sort | cmp -s - "$tmp/in-dylib" || bad "libRecaulkSystem.dylib does not carry exactly every member's notice"

"$NM" -gU "$lib" 2>/dev/null | awk 'NF == 3 { print $3 }' | sort -u > "$tmp/lib-globals"
fx="$tmp/fixture"
cp -R "$mpdir" "$fx"
printf '#include "atcalls.h"\n' > "$fx/src/apsl_between.h"
for c in fdopendir statxx; do
  grep -q '^#include "atcalls.h"' "$fx/src/$c.c" || bad "the fixture expects MacPorts' $c.c to include atcalls.h directly"
  sed 's/^#include "atcalls.h"/#include "apsl_between.h"/' "$mp/$c.c" > "$fx/src/$c.c"
done
rc=0; AR="$AR" CC="$CC" MP_CFLAGS="$FLAGS" sh build/apsl-notices.sh "$fx" "$tmp/fx-out" > "$tmp/fx.log" 2>&1 || rc=$?
got="$(tr '\n' ' ' < "$tmp/fx.log")"
[ "$rc" = 0 ] || bad "build/apsl-notices.sh failed (rc $rc) on a tree whose atcalls.h arrives through another header: $got"
for c in atcalls fdopendir statxx utimensat; do
  case " $got" in *" $c "*) ;; *) bad "build/apsl-notices.sh missed $c when atcalls.h arrives through another header: $got" ;; esac
done
{
  printf '/*\n * Copyright (c) 1999 Apple Computer, Inc.\n * @APPLE_LICENSE_HEADER_START@\n'
  printf ' * subject to the Apple Public Source License Version 1.1 (the "License").\n'
  printf ' * @APPLE_LICENSE_HEADER_END@\n */\n/* Not Version 2.0 of anything. */\n'
} > "$fx/src/apsl_one.h"
printf '#include "apsl_one.h"\n' >> "$fx/src/apsl_between.h"
rc=0; AR="$AR" CC="$CC" MP_CFLAGS="$FLAGS" sh build/apsl-notices.sh "$fx" "$tmp/fx-out" > "$tmp/fx.log" 2>&1 || rc=$?
[ "$rc" = 1 ] && grep -q 'not APSL 2.0' "$tmp/fx.log" \
  || bad "an APSL 1.1 header that mentions Version 2.0 passed as APSL 2.0 (rc $rc): $(cat "$tmp/fx.log")"

ld="-fuse-ld=lld --ld-path=$CL/bin/ld64.lld"
fw="-framework CoreFoundation -framework Security -framework CoreVideo -framework CoreGraphics -framework CoreServices -framework IOKit -lobjc -lc++abi"
link_proof() {
  _m="$1"; _s="$2"; _kind="$3"
  printf '.text\n.globl _main\n_main:\n  pushq %%rbp\n  callq "%s"\n  popq %%rbp\n  ret\n' "$_s" > "$tmp/use.s"
  "$CC" $FLAGS -arch x86_64 -c "$tmp/use.s" -o "$tmp/use.o"
  if [ "$_kind" = dylib ]; then
    out="$tmp/use.dylib"
    "$CC" $FLAGS -arch x86_64 $ld -dynamiclib -Wl,-dead_strip -o "$out" "$tmp/use.o" "$lib" $fw '-Wl,-unexported_symbol,___recaulk_*' 2> "$tmp/link.err" \
      || { bad "a -dead_strip dylib using $_s did not link: $(cat "$tmp/link.err")"; return; }
  else
    out="$tmp/use"
    "$CC" $FLAGS -arch x86_64 $ld -Wl,-dead_strip -o "$out" "$tmp/use.o" "$lib" $fw 2> "$tmp/link.err" \
      || { bad "a -dead_strip program using $_s did not link: $(cat "$tmp/link.err")"; return; }
  fi
  new="$("$NM" -gU "$out" | awk '{ print $3 }' | sort | comm -23 - "$tmp/lib-globals" \
    | grep -vx -e _main -e __mh_execute_header | tr '\n' ' ')" || :
  [ -z "$new" ] || bad "a $_kind pulling in $_m exports what librecaulk.a does not: $new"
  want="$(awk -F '\t' -v m="$_m" '$1 == m { print $2 }' "$tmp/embedded")"
  "$STRINGS" -a "$out" | grep -qxF "$want" || bad "ld64.lld -dead_strip dropped $_m's notice from a $_kind that calls $_s"
  "$NM" "$out" | grep -q ' s _recaulk_apsl_notice$' || bad "the $_kind that calls $_s lost the notice's local symbol"
}
while IFS= read -r m; do
  s="$("$NM" -gU "$tmp/x/$m" | awk '$2 == "T" { print $3; exit }')"
  [ -n "$s" ] || { bad "$m defines no function to link it by"; continue; }
  case "$s" in ___recaulk_impl_*) s="_${s#___recaulk_impl_}" ;; esac
  link_proof "$m" "$s" program
  link_proof "$m" "$s" dylib
done < "$tmp/have"

printf '.text\n.globl _main\n_main:\n  pushq %%rbp\n  callq _strtonum\n  popq %%rbp\n  ret\n' > "$tmp/plain.s"
"$CC" $FLAGS -arch x86_64 -c "$tmp/plain.s" -o "$tmp/plain.o"
"$CC" $FLAGS -arch x86_64 $ld -Wl,-dead_strip -o "$tmp/plain" "$tmp/plain.o" "$lib" $fw 2> "$tmp/link.err" \
  || bad "a program using only strtonum did not link: $(cat "$tmp/link.err")"
"$STRINGS" -a "$tmp/plain" | grep -q '^Recaulk member ' && bad "a program pulling in no Apple-derived member carries an APSL notice"

[ "$fail" = 0 ] && echo "apsl-notices OK: $(tr '\n' ' ' < "$tmp/have")"
exit $fail
