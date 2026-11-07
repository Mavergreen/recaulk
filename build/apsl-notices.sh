#!/bin/sh
# platform: host-agnostic
#   usage: sh build/apsl-notices.sh MPSRC OUT     for each member of MPSRC/lib/libMacportsLegacySupport.a whose
#          source, or a header it includes by "name" from its own directory, carries Apple's licence header:
#          writes OUT/<stem>.h (the member's notice, as a local no-dead-strip string), OUT/notices.mk (a
#          makefile that compiles each such member with its notice) and OUT/rows.tsv (artifact-less
#          notices.tsv rows: member, licence, covered files, copyright, source URLs, notice); prints the
#          stems. Refuses, exit 1, an Apple-licensed source whose licence is not APSL 2.0, and any of
#          Recaulk's own sources that carries an Apple licence.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"
[ $# -eq 2 ] || { sed -n 's/^#   usage: //p' "$0" >&2; exit 2; }
mp="$1"; out="$2"
apple='[Cc]opyright.*Apple|Apple Public Source|APPLE_LICENSE_HEADER'
repo="$(macports_pin REPO)"; repo="${repo%.git}"
digest="$(macports_pin DIGEST)"
rel=https://github.com/Mavergreen/recaulk/releases

own="$(cd "$MAVERICKS_ROOT" && grep -El "$apple" src/backfills/* src/overrides/* src/forward/* src/*.h 2>/dev/null || :)"
[ -z "$own" ] || { echo "apsl-notices: Recaulk's own $own carries an Apple licence; its members need a notice this script does not give" >&2; exit 1; }

apsl2() {
  grep -q 'Apple Public Source License' "$1" && grep -q 'Version 2\.0' "$1"
}

rm -rf "$out"; mkdir -p "$out"
: > "$out/notices.mk"; : > "$out/rows.tsv"
"${AR:?apsl-notices: AR (llvm-ar) required}" t "$mp/lib/libMacportsLegacySupport.a" | sed -n 's/\.o$//p' | LC_ALL=C sort > "$out/members"
while IFS= read -r stem; do
  c="src/$stem.c"
  [ -f "$mp/$c" ] || { echo "apsl-notices: MacPorts member $stem.o has no $c, so whether it is Apple-derived cannot be read" >&2; exit 1; }
  covered=""
  for f in "$c" $(sed -n 's/^[[:space:]]*#[[:space:]]*include[[:space:]]*"\([^"]*\)".*/src\/\1/p' "$mp/$c"); do
    [ -f "$mp/$f" ] && grep -Eq "$apple" "$mp/$f" || continue
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
