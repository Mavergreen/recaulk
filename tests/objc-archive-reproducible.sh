#!/bin/sh
# platform: host-agnostic
# spec: build/build-objc.sh -- librecaulk-objc.a is the same bytes from any checkout and work directory. -g line
#       tables and the compilation directory name sources by the relative labels source-inputs.txt (and so the
#       receipt) records, never by the absolute path a build happened to use.
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
. "$ROOT/build/msc.sh"
fail() { echo "FAIL: $*"; exit 1; }
D=$(mktemp -d "${TMPDIR:-/tmp}/objc-archive-reproducible.XXXXXX")
D=$(cd "$D" && pwd -P)
trap 'rm -rf "$D"' EXIT
# spec: build/build-objc.sh prefix maps -- two checkouts at different paths and path lengths, each with its own
#       work directory, must build the same bytes
for c in a checkout-at-a-longer-path; do
  mkdir -p "$D/$c"
  (cd "$ROOT" && tar -cf - --exclude ./.git --exclude ./.superpowers .) | (cd "$D/$c" && tar -xf -)
  # platform: build/lib.sh exports MAVERICKS_ROOT, which would point every copy's build back at $ROOT
  env -u MAVERICKS_ROOT sh "$D/$c/build/build-objc.sh" "$D/stage-$c" "$D/work-$c" > "$D/$c.log" 2>&1 || { tail -20 "$D/$c.log"; fail "build from $c"; }
done
A=$D/stage-a/lib/librecaulk-objc.a
cmp -s "$A" "$D/stage-checkout-at-a-longer-path/lib/librecaulk-objc.a" ||
  fail 'two checkouts at different paths build different librecaulk-objc.a bytes'
echo 'objc-archive-reproducible: two checkouts at different paths build identical archives'
[ -f "$D/work-a/sdk.txt" ] || fail 'build-objc.sh recorded no SDK path in work/sdk.txt'
SDKP=$(sed -n 's/^SDK=//p' "$D/work-a/sdk.txt")
[ -n "$SDKP" ] || fail 'build-objc.sh recorded no SDK path in work/sdk.txt'
for p in "$ROOT" "$D/a" "$D/work-a" "$D" "$SDKP" "$HOME"; do
  ! LC_ALL=C grep -F "$p" "$A" > /dev/null || fail "librecaulk-objc.a embeds the build path $p"
done
echo 'objc-archive-reproducible: the archive embeds no checkout, work, temporary, SDK or home path'
. "$ROOT/build/lib.sh"
recaulk_tools
DWARFDUMP=${DWARFDUMP:-$(dirname "$CC")/llvm-dwarfdump}
mkdir "$D/members"
(cd "$D/members" && "$AR" x "$A")
while read -r sha label; do
  case $label in *.m) ;; *) continue ;; esac
  o=$D/members/$(basename "$label" .m).o
  [ -f "$o" ] || fail "no archive member for $label"
  if [ -x "$DWARFDUMP" ]; then
    "$DWARFDUMP" --debug-info --debug-line "$o" > "$D/dwarf.txt"
    grep -E "DW_AT_name.*\"$label\"" "$D/dwarf.txt" > /dev/null ||
      fail "$label's compile unit is not named by its receipt label: $(grep -m1 DW_AT_name "$D/dwarf.txt")"
    grep -E 'DW_AT_comp_dir.*"\."' "$D/dwarf.txt" > /dev/null ||
      fail "$label's compilation directory is not \".\": $(grep -m1 DW_AT_comp_dir "$D/dwarf.txt")"
  else
    # platform: the Linux clang22 archive carries Mach-O readers but no llvm-dwarfdump (build/fetch-clang22.sh), so
    #           there the label is checked as a whole string of the member; the path ban above covers the rest
    "$STRINGS" -a "$o" | grep -Fx "$label" > /dev/null || fail "$label is not a whole string of its member"
  fi
done < "$D/work-a/source-inputs.txt"
echo 'objc-archive-reproducible: each unit names its source by the label the receipt records'
