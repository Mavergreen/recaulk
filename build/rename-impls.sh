#!/bin/sh
# platform: macOS-only -- nm reads Mach-O objects
set -eu
[ $# -ge 3 ] || { echo "usage: sh build/rename-impls.sh DRYDOCK SYMLIST OBJ... -- in each OBJ, renames each _<n> of SYMLIST that OBJ defines to ___recaulk_impl_<n>, in place" >&2; exit 2; }
drydock="$1"; symlist="$2"; shift 2
[ -s "$symlist" ] || { echo "rename-impls: $symlist is empty or missing" >&2; exit 1; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/rename-impls.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
LC_ALL=C sort -u "$symlist" > "$tmp/F"

for obj in "$@"; do
  nm -gU "$obj" | awk 'NF == 3 && $2 == "T" { print $3 }' | LC_ALL=C sort -u > "$tmp/T"
  LC_ALL=C comm -12 "$tmp/T" "$tmp/F" > "$tmp/defs"
  [ -s "$tmp/defs" ] || continue
  script="$obj.drydock"
  {
    echo allow-unmatched
    while IFS= read -r sym; do
      n="${sym#_}"
      printf 'symbol rename _%s ___recaulk_impl_%s\n' "$n" "$n"
      printf 'symbol rename _%s.eh ___recaulk_impl_%s.eh\n' "$n" "$n"
    done < "$tmp/defs"
  } > "$script"
  if ! "$drydock" "$obj" "$obj.renamed" < "$script" > "$obj.rename.log" 2>&1; then
    cat "$obj.rename.log" >&2
    rm -f "$obj.renamed"
    echo "rename-impls: drydock refused $obj (script $script)" >&2
    exit 1
  fi
  mv -f "$obj.renamed" "$obj"
  rm -f "$obj.rename.log"
done
