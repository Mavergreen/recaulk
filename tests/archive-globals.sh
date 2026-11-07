#!/bin/sh
# platform: host-agnostic -- nm reads Mach-O archives
# spec: README.md "How to use" -- every global a shipped archive defines, private externs included (nm prints
#       them as globals, and so does a consumer that picks members by name, as Swift's recaulk_subset does), is
#       a named API or ___recaulk_-prefixed. A named API is a name build/forward-exclude.txt does not class
#       private: an external one, or a hidden copy build/image-local-shadows.txt lists for its member.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
tmp="$(mktemp -d "${TMPDIR:-/tmp}/archive-globals.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
awk '$3 == "private" { print $1, $2 }' build/forward-exclude.txt > "$tmp/private"
awk '!/^#/ && NF >= 2 { print $1, $2 }' build/image-local-shadows.txt > "$tmp/shadows"
[ -s "$tmp/private" ] || { echo "FAIL: build/forward-exclude.txt classes nothing private"; exit 1; }
for a in librecaulk.a librecaulk-cxxabi-exports.a; do
  "$NM" -m -A "$T/lib/$a" > "$tmp/nm" || { echo "FAIL: $NM could not read $T/lib/$a"; exit 1; }
  [ -s "$tmp/nm" ] || { echo "FAIL: no symbols read from $T/lib/$a"; exit 1; }
  awk -v A="$a" -v P="$tmp/private" -v S="$tmp/shadows" '
    BEGIN {
      while ((getline l < P) > 0) { split(l, f, " "); if (f[1] == "prefix") pre[++np] = f[2]; else ex[f[2]] = 1 }
      while ((getline l < S) > 0) { split(l, f, " "); shadow[f[1] " " f[2]] = 1 }
    }
    /\(undefined\)/ || / non-external / { next }
    {
      m = $1; sub(/:$/, "", m); sub(/^.*\.a:/, "", m); n = $NF; b = n; sub(/\.eh$/, "", b)
      if (b ~ /^___recaulk_/) next
      priv = (b in ex); for (i = 1; i <= np; i++) if (index(b, pre[i]) == 1) priv = 1
      if (priv) { print "FAIL: " A "(" m ") defines " n ", which build/forward-exclude.txt classes private: name it ___recaulk_"; bad = 1 }
      else if (/private external/ && !((m " " b) in shadow)) {
        print "FAIL: " A "(" m ") defines the private external " n ", which nm reads as a global and build/image-local-shadows.txt does not list: name it ___recaulk_"; bad = 1
      }
    }
    END { exit bad }' "$tmp/nm" || fail=1
done
[ "$fail" = 0 ] && echo "archive globals OK"
exit "$fail"
