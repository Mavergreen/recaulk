#!/bin/sh
# platform: host-agnostic
#   usage: AR=<llvm-ar> CC=<clang> MP_CFLAGS=<the build's CFLAGS> sh build/apsl-notices.sh MPSRC OUT
#          For each member of MPSRC/lib/libMacportsLegacySupport.a for which anything clang -M says its
#          source reads, but the SDK and the compiler's own headers, carries Apple's licence mark (a header
#          in build/apsl-declaration-only.txt is exempt at its listed sha256 only): writes OUT/<stem>.h (the
#          member's notice, as a local no-dead-strip string), OUT/notices.mk (a makefile that compiles each
#          such member with its notice) and OUT/rows.tsv (artifact-less notices.tsv rows: member, licence,
#          covered files, Apple copyright lines, source URLs, notice); prints the stems. Refuses, exit 1,
#          an Apple-marked file whose licence is not APSL 2.0, a file it cannot read, and any of Recaulk's
#          own sources that carries an Apple mark.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"
[ $# -eq 2 ] || { sed -n 's/^#   usage: //p' "$0" >&2; exit 2; }
mp="$(cd "$1" && pwd)"; out="$2"
: "${AR:?apsl-notices: AR (llvm-ar) required}" "${CC:?apsl-notices: CC (clang22) required}"
: "${MP_CFLAGS?apsl-notices: MP_CFLAGS (the flags the build gives MacPorts as CFLAGS) required}"
apple='[Cc]opyright.*Apple|Apple Public Source|APPLE_LICENSE_HEADER'
allow="$SELF/apsl-declaration-only.txt"
repo="$(macports_pin REPO)"; repo="${repo%.git}"
digest="$(macports_pin DIGEST)"
rel=https://github.com/Mavergreen/recaulk/releases

marked() {
  _mk=0; grep -Eq "$apple" "$1" || _mk=$?
  [ "$_mk" -le 1 ] || { echo "apsl-notices: cannot read $1 (grep exit $_mk), so whether it is Apple-licensed is unknown" >&2; exit 1; }
  return "$_mk"
}

apsl2() {
  awk '{ l = $0; gsub(/[*\/ \t]+/, " ", l); t = t " " l } END { gsub(/ +/, " ", t); exit !(t ~ /Apple Public Source License Version 2\.0/) }' "$1"
}

exempt() {
  _ex="$(shasum -a 256 < "$mp/$1" | cut -c1-64)"
  awk -v p="$1" -v h="$_ex" '$1 == h && $2 == p { f = 1 } END { exit !f }' "$allow"
}

rm -rf "$out"; mkdir -p "$out"
find "$MAVERICKS_ROOT/src" -type f > "$out/own" || { echo "apsl-notices: cannot list $MAVERICKS_ROOT/src" >&2; exit 1; }
[ -s "$out/own" ] || { echo "apsl-notices: $MAVERICKS_ROOT/src holds no files" >&2; exit 1; }
while IFS= read -r f; do
  if marked "$f"; then echo "apsl-notices: Recaulk's own $f carries an Apple licence mark; its members need a notice this script does not give" >&2; exit 1; fi
done < "$out/own"

: > "$out/notices.mk"; : > "$out/rows.tsv"
"${AR:?apsl-notices: AR (llvm-ar) required}" t "$mp/lib/libMacportsLegacySupport.a" | sed -n 's/\.o$//p' | LC_ALL=C sort > "$out/members"
while IFS= read -r stem; do
  c="src/$stem.c"
  [ -f "$mp/$c" ] || { echo "apsl-notices: MacPorts member $stem.o has no $c, so whether it is Apple-derived cannot be read" >&2; exit 1; }
  deps="$(cd "$mp" && "$CC" -Iinclude -arch x86_64 -Os $MP_CFLAGS -M -MT x "$c")" \
    || { echo "apsl-notices: clang -M could not list what $c includes" >&2; exit 1; }
  covered=""
  for f in $(printf '%s\n' "$deps" | tr '\\' ' '); do
    case "$f" in x:|/*) continue ;; ./*) f="${f#./}" ;; esac
    marked "$mp/$f" || continue
    exempt "$f" && continue
    apsl2 "$mp/$f" || { echo "apsl-notices: $f (in $stem.o) carries an Apple licence that is not APSL 2.0; decide its notice before shipping it" >&2; exit 1; }
    case " $covered " in *" $f "*) ;; *) covered="${covered:+$covered }$f" ;; esac
  done
  [ -n "$covered" ] || continue
  m="mp-$stem.o"
  copy="$(for f in $covered; do sed -n 's/^[[:space:]*/]*\(Copyright.*Apple.*\)$/\1/p' "$mp/$f"; done \
    | awk '!seen[$0]++ { printf "%s%s", (n++ ? "; " : ""), $0 }')"
  urls=""
  for f in $covered; do
    urls="${urls:+$urls }$repo/blob/$digest/$f"
  done
  [ -n "$copy" ] || { echo "apsl-notices: no Apple copyright line in $covered" >&2; exit 1; }
  notice="Recaulk member $m is object code compiled from $c of MacPorts legacy-support and contains Covered Code from $(printf '%s' "$covered" | sed 's/ /, /g') ($copy). Source Code of the Covered Code is available under the terms of the Apple Public Source License Version 2.0 (https://opensource.apple.com/apsl/) at $(printf '%s' "$urls" | sed 's/ / and /g'). Recaulk's own source, which builds this member, is with each Recaulk release at $rel"
  case "$notice" in *'"'*|*'\'*|*"$(printf '\t')"*) echo "apsl-notices: $m's notice holds a quote, backslash or tab: $notice" >&2; exit 1 ;; esac
  printf 'static const char recaulk_apsl_notice[] __attribute__((used, section("__TEXT,__recaulk_apsl"))) =\n  "%s";\n' "$notice" > "$out/$stem.h"
  printf '$(BUILDDIR)/%s$(SLIBOBJEXT): SLIBCFLAGS += -include %s/%s.h\n' "$stem" "$out" "$stem" >> "$out/notices.mk"
  printf '%s\tAPSL-2.0\t%s\t%s\t%s\t%s\n' "$m" "$(printf '%s' "$covered" | tr ' ' ',')" "$copy" "$urls" "$notice" >> "$out/rows.tsv"
  printf '%s\n' "$stem"
done < "$out/members"
