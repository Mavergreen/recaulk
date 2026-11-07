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
set -- "$W"/macports-legacy-support-*/src
mp="$1"
[ -d "$mp" ] || { echo "FAIL: no MacPorts source under $W"; exit 1; }
digest="$(macports_pin DIGEST)"
apple='[Cc]opyright.*Apple|Apple Public Source|APPLE_LICENSE_HEADER'

apple_derived() {
  grep -Eq "$apple" "$1" && return 0
  for h in $(sed -n 's/^[[:space:]]*#[[:space:]]*include[[:space:]]*"\([^"]*\)".*/\1/p' "$1"); do
    [ -f "$(dirname "$1")/$h" ] && grep -Eq "$apple" "$(dirname "$1")/$h" && return 0
  done
  return 1
}

"$AR" t "$lib" | grep -v '^__\.SYMDEF' | sort > "$tmp/members"
: > "$tmp/expect"
while IFS= read -r m; do
  case "$m" in
    mp-*.o) src="$mp/${m#mp-}"; src="${src%.o}.c" ;;
    recaulk-*.o) stem="${m#recaulk-}"; stem="${stem%.o}"; src="$MAVERICKS_ROOT/src/backfills/$stem.c" ;;
    *) continue ;;
  esac
  [ -f "$src" ] || { bad "$m has no source at $src, so whether it is Apple-derived cannot be read"; continue; }
  if apple_derived "$src"; then echo "$m" >> "$tmp/expect"; fi
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
