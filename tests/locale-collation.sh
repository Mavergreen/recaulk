#!/bin/sh
# platform: macOS-only -- runs artifacts.sh and fetch-drydock.sh, which inspect Mach-O files and build pkgs
set -eu
cd "$(dirname "$0")/.."
D="$(mktemp -d "${TMPDIR:-/tmp}/locale-collation.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# platform: macOS 26's en_US.UTF-8 collation ignores case in ls and sort, where 10.9's compares bytes; these stubs fold case as 26 does
mkdir "$D/bin"
cat > "$D/bin/sort" <<'EOF'
#!/bin/sh
case "${LC_ALL:-${LC_COLLATE:-${LANG:-}}}" in C|POSIX) exec /usr/bin/sort "$@" ;; esac
exec /usr/bin/sort -f "$@"
EOF
cat > "$D/bin/ls" <<'EOF'
#!/bin/sh
case "${LC_ALL:-${LC_COLLATE:-${LANG:-}}}" in C|POSIX) exec /bin/ls "$@" ;; esac
out="$(/bin/ls "$@")" || exit $?
[ -z "$out" ] || printf '%s\n' "$out" | LC_ALL=C /usr/bin/sort -f
EOF
chmod +x "$D/bin/sort" "$D/bin/ls"

folded() { (unset LC_ALL LC_COLLATE; LANG=en_US.UTF-8; PATH="$D/bin:$PATH"; export LANG PATH; "$@"); }
mkdir "$D/names"
: > "$D/names/SHA256SUMS"; : > "$D/names/drydock-0.0.1.pkg"
[ "$(folded ls "$D/names" | tr '\n' ' ')" = "drydock-0.0.1.pkg SHA256SUMS " ] \
  || bad "the ls stub does not fold case, so this test would prove nothing: $(folded ls "$D/names" | tr '\n' ' ')"
[ "$(printf 'Security\nlibobjc.A.dylib\n' | folded sort | tr '\n' ' ')" = "libobjc.A.dylib Security " ] \
  || bad "the sort stub does not fold case, so this test would prove nothing"

for t in artifacts fetch-drydock; do
  rc=0
  out="$(folded sh "tests/$t.sh" 2>&1)" || rc=$?
  case "$rc" in
    0) ;;
    77) echo "SKIP: tests/$t.sh skipped: $out"; exit 77 ;;
    *) bad "tests/$t.sh fails under a collation that ignores case (exit $rc):"; printf '%s\n' "$out" | sed 's/^/  /' ;;
  esac
done

[ "$fail" = 0 ] && echo "locale-collation OK"
exit $fail
