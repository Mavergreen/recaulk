#!/bin/sh
# platform: host-agnostic
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 2 ] || { echo "usage: sh build/rename-private.sh DRYDOCK OBJ... -- in each OBJ, renames to ___recaulk_<name> every name build/forward-exclude.txt classes private, and every private external it defines that build/image-local-shadows.txt does not list, in place" >&2; exit 2; }
drydock="$1"; shift
tmp="$(mktemp -d "${TMPDIR:-/tmp}/rename-private.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
awk '$3 == "private" { print $1, $2 }' "$SELF/forward-exclude.txt" > "$tmp/private"
awk '!/^#/ && NF >= 2 { print $1, $2 }' "$SELF/image-local-shadows.txt" > "$tmp/shadows"

for obj in "$@"; do
  "${NM:-nm}" -m "$obj" > "$tmp/nm" || { echo "rename-private: ${NM:-nm} -m failed on $obj" >&2; exit 1; }
  awk -v M="$(basename "$obj")" -v P="$tmp/private" -v S="$tmp/shadows" '
    BEGIN {
      while ((getline l < P) > 0) { split(l, f, " "); if (f[1] == "prefix") pre[++np] = f[2]; else ex[f[2]] = 1 }
      while ((getline l < S) > 0) { split(l, f, " "); if (f[1] == M) shadow[f[2]] = 1 }
    }
    / non-external / { next }
    {
      n = $NF
      if (n ~ /\.eh$/ || n ~ /^___recaulk_/) next
      priv = (n in ex); for (i = 1; i <= np; i++) if (index(n, pre[i]) == 1) priv = 1
      hidden = !/\(undefined\)/ && /private external/ && !(n in shadow)
      if (priv || hidden) print n
    }' "$tmp/nm" | LC_ALL=C sort -u > "$tmp/names"
  [ -s "$tmp/names" ] || continue
  script="$obj.private.drydock"
  {
    echo allow-unmatched
    while IFS= read -r n; do
      new="___recaulk_$(printf '%s' "$n" | sed 's/^_*//')"
      if awk -v s="$new" '$NF == s' "$tmp/nm" | grep -q .; then
        echo "rename-private: $obj already names $new, the private name for $n" >&2; exit 1
      fi
      printf 'symbol rename %s %s\n' "$n" "$new"
      printf 'symbol rename %s.eh %s.eh\n' "$n" "$new"
    done < "$tmp/names"
  } > "$script"
  if ! "$drydock" "$obj" "$obj.renamed" < "$script" > "$obj.rename.log" 2>&1; then
    cat "$obj.rename.log" >&2
    rm -f "$obj.renamed"
    echo "rename-private: drydock refused $obj (script $script)" >&2
    exit 1
  fi
  mv -f "$obj.renamed" "$obj"
  rm -f "$obj.rename.log" "$script"
done
