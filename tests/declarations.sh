#!/bin/sh
# platform: host-agnostic -- compiles against the 10.9 SDK
# spec: README.md "Declarations" -- every public function librecaulk.a defines is in build/declarations.txt,
#       and each one listed with a header is declared by that header under -isystem include/recaulk. An
#       undeclared backfill is worse than none: autoconf's link test finds it, the program drops its own
#       fallback, and a C99 compiler then refuses the call (LibreSSL's timingsafe_bcmp, 2026-11-07).
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
d="$(mktemp -d "${TMPDIR:-/tmp}/declarations.XXXXXX")"
trap 'rm -rf "$d"' EXIT
list=build/declarations.txt

# Public: an external (not private external) text symbol, not Recaulk's internal ___recaulk_ name, not a
# $-variant of a function 10.9 has (README.md "Fixes to functions 10.9 has"), and not C++.
"$NM" -m --defined-only "$T/lib/librecaulk.a" > "$d/nm" || { echo "FAIL: $NM cannot read librecaulk.a"; exit 1; }
grep ' external ' "$d/nm" | grep -v 'private external' | grep '(__TEXT,__text)' | awk '{ print $NF }' \
  | sed 's/^_//' | grep -v -e '^__recaulk_' -e '\$' -e '^_Z' | LC_ALL=C sort -u > "$d/defined"
[ -s "$d/defined" ] || bad "found no public functions in librecaulk.a"
grep -v -e '^#' -e '^[[:space:]]*$' "$list" | awk '{ print $1 }' | LC_ALL=C sort > "$d/listed"
dups="$(uniq -d "$d/listed")"
[ -z "$dups" ] || bad "$list lists more than once: $(echo $dups)"
for n in $(LC_ALL=C comm -23 "$d/defined" "$d/listed"); do bad "librecaulk.a defines $n, which $list does not list"; done
for n in $(LC_ALL=C comm -13 "$d/defined" "$d/listed"); do bad "$list lists $n, which librecaulk.a does not define publicly"; done
grep -v -e '^#' -e '^[[:space:]]*$' "$list" | awk '$2 == "-" && NF < 3 { print "FAIL: " $1 " is ABI-only with no reason" }' > "$d/noreason"
[ ! -s "$d/noreason" ] || { cat "$d/noreason"; fail=1; }

# One translation unit per header (and language), taking each listed name's address, so an undeclared
# one is clang's "use of undeclared identifier".
grep -v -e '^#' -e '^[[:space:]]*$' "$list" | awk '$2 != "-" { print $2, ($3 == "c++" ? "cpp" : "c"), ($3 == "c++" ? $4 : $1) }' \
  | LC_ALL=C sort > "$d/byheader"
for hl in $(awk '{ print $1 "|" $2 }' "$d/byheader" | uniq); do
  h="${hl%|*}"; lang="${hl#*|}"; src="$d/$(echo "$h" | tr '/.' '__').$lang"
  {
    echo "#include <$h>"
    awk -v h="$h" -v l="$lang" '$1 == h && $2 == l { print "void *recaulk_declared_" NR " = (void *)&" $3 ";" }' "$d/byheader"
  } > "$src"
  if "$CC" $FLAGS -isystem "$T/include/recaulk" -fsyntax-only -ferror-limit=0 -w "$src" 2> "$d/err"; then :; else
    und="$(grep -o "undeclared identifier '[^']*'" "$d/err" | sed "s/.*'\(.*\)'/\1/" | LC_ALL=C sort -u)"
    if [ -n "$und" ]; then
      for n in $und; do bad "<$h> does not declare $n"; done
    else
      bad "<$h> does not compile: $(grep -m 1 'error:' "$d/err")"
    fi
  fi
done
[ "$fail" = 0 ] && echo "PASS: every public function librecaulk.a defines is declared where $list says"
exit "$fail"
