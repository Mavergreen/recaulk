#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
git --version >/dev/null 2>&1 || { echo "no git that runs -- skipping"; exit 77; }
[ -f "$ROOT/build/pins-bot.sh" ] || fail "build/pins-bot.sh does not exist"
T="$(mktemp -d "${TMPDIR:-/tmp}/pins-bot.XXXXXX")"
trap 'rm -rf "$T"' EXIT
R="$T/repo"; REL=components/macports-legacy-support/version; V="$R/$REL"
mkdir -p "$R/build" "$R/components/macports-legacy-support"
cp "$ROOT/build/pins-bot.sh" "$R/build/"; cp "$ROOT/$REL" "$V"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" add -A; git -C "$R" commit -qm main; git -C "$R" branch -m main
bot() { ( cd "$R" && sh build/pins-bot.sh "$@" ); }
Z=0000000000000000000000000000000000000000000000000000000000000000
edit() { sed "s|^$1=.*|$1=$2|" "$V" > "$T/p" && cat "$T/p" > "$V"; }

echo "-- moved: an unrelated line is not a pin; a moved DIGEST is, even after main moved on"
git -C "$R" checkout -q -b renovate/other; echo "OTHER=1" >> "$V"; git -C "$R" commit -qam other
if bot moved main > "$T/out"; then fail "an unrelated line counted as a moved pin: $(cat "$T/out")"; fi
git -C "$R" checkout -q main; edit TARBALL_SHA256 "$Z"; git -C "$R" commit -qam later
git -C "$R" checkout -q -b renovate/macports HEAD~1; edit DIGEST 1111111111111111111111111111111111111111; git -C "$R" commit -qam macports
bot moved main > "$T/out" || fail "a moved DIGEST was not seen"
[ "$(grep -c '^[-+]DIGEST=' "$T/out")" = 2 ] && [ "$(wc -l < "$T/out" | tr -d ' ')" = 2 ] || fail "moved printed: $(cat "$T/out")"

echo "-- values: the pin on one line; a bad one refused"
[ "$(bot values)" = "TARBALL_SHA256=$(sed -n 's/^TARBALL_SHA256=//p' "$ROOT/$REL")" ] || fail "values: $(bot values)"
edit TARBALL_SHA256 abc
if bot values > /dev/null 2> "$T/err"; then fail "handed on TARBALL_SHA256=abc"; fi
grep -q "TARBALL_SHA256 is 'abc'" "$T/err" || fail "values: $(cat "$T/err")"
cp "$ROOT/$REL" "$V"

echo "-- apply: the one line, nothing else; unchanged when it holds the value; refusals write nothing"
cp "$V" "$T/before"
[ "$(bot apply TARBALL_SHA256=$Z)" = changed ] || fail "apply did not say changed"
[ "$(diff "$T/before" "$V" | grep -c '^>')" = 1 ] || fail "apply changed: $(diff "$T/before" "$V")"
grep -qx "TARBALL_SHA256=$Z" "$V" || fail "TARBALL_SHA256 not written"
[ "$(bot apply TARBALL_SHA256=$Z)" = unchanged ] || fail "a second apply of the same value changed the file"
cp "$V" "$T/now"
for bad in "DIGEST=$Z" "REF=v9" "TARBALL_SHA256=${Z%0}" "TARBALL_SHA256=$Z TARBALL_SHA256=$Z" "TARBALL_SHA256=\$(touch $T/pwned)"; do
  # shellcheck disable=SC2086
  if bot apply $bad > /dev/null 2>&1; then fail "applied [$bad]"; fi
  cmp -s "$T/now" "$V" || fail "a refused [$bad] wrote the pin file"
done
[ ! -e "$T/pwned" ] || fail "apply ran a value"
grep -v '^TARBALL_SHA256=' "$T/now" > "$V"; cp "$V" "$T/nopin"
if bot apply TARBALL_SHA256=$Z > /dev/null 2> "$T/err"; then fail "apply succeeded on a pin file with no TARBALL_SHA256 line"; fi
grep -q 'has no TARBALL_SHA256 line' "$T/err" || fail "apply, no TARBALL_SHA256 line: said [$(cat "$T/err")]"
cmp -s "$T/nopin" "$V" || fail "apply wrote a pin file that has no TARBALL_SHA256 line"
cp "$T/now" "$V"

echo "-- fill: --check 0 nothing to do; 3 the write, then the values; anything else fails, writing nothing"
git -C "$R" checkout -q -- "$REL"
E=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
cat > "$R/build/pin-source-tarball.sh" <<'STUB'
#!/bin/sh
echo "${1:-write}" >> "$STUB_LOG"
case "${1:-}" in --check) exit "$STUB_CHECK" ;; esac
[ "$STUB_WRITE" = 0 ] || exit "$STUB_WRITE"
p="$(dirname "$0")/../components/macports-legacy-support/version"
sed "s|^TARBALL_SHA256=.*|TARBALL_SHA256=$STUB_SHA|" "$p" > "$p.new" && mv "$p.new" "$p"
STUB
fill() {
  : > "$T/calls"
  ( cd "$R" && env STUB_LOG="$T/calls" STUB_CHECK="$2" STUB_WRITE="$3" STUB_SHA="$E" sh build/pins-bot.sh fill "$1" ) > "$T/out" 2> "$T/err"
}
calls() { tr '\n' ' ' < "$T/calls" | sed 's/ $//'; }
git -C "$R" checkout -q renovate/macports
cp "$V" "$T/now"
fill main 0 0 || fail "fill, --check current: exit $? ($(cat "$T/err"))"
[ ! -s "$T/out" ] && [ "$(calls)" = --check ] || fail "fill, --check current: handed on [$(cat "$T/out")], calls [$(calls)]"
cmp -s "$T/now" "$V" || fail "fill, --check current: the pin file changed"
fill main 3 0 || fail "fill, --check stale: exit $? ($(cat "$T/err"))"
[ "$(calls)" = "--check write" ] || fail "fill, --check stale: calls [$(calls)]"
[ "$(cat "$T/out")" = "TARBALL_SHA256=$E" ] || fail "fill, --check stale: handed on [$(cat "$T/out")]"
cp "$T/now" "$V"
for rc in 1 2 130 143 7; do
  if fill main "$rc" 0; then fail "fill, --check exit $rc: exit 0, handed on [$(cat "$T/out")]"; fi
  [ ! -s "$T/out" ] && [ "$(calls)" = --check ] || fail "fill, --check exit $rc: handed on [$(cat "$T/out")], calls [$(calls)]"
  cmp -s "$T/now" "$V" || fail "fill, --check exit $rc: the pin file changed"
done
grep -q 'pin-source-tarball.sh --check exited 7' "$T/err" || fail "fill, --check exit 7: said [$(cat "$T/err")]"
if fill main 3 1; then fail "fill, a failed write: exit 0"; fi
[ ! -s "$T/out" ] && [ "$(calls)" = "--check write" ] || fail "fill, a failed write: handed on [$(cat "$T/out")], calls [$(calls)]"
if fill nosuchref 3 0; then fail "fill, no merge base: exit 0"; fi
[ ! -s "$T/out" ] && [ ! -s "$T/calls" ] || fail "fill, no merge base: handed on [$(cat "$T/out")], calls [$(calls)]"
git -C "$R" checkout -q renovate/other
fill main 3 0 || fail "fill, an unrelated change: exit $? ($(cat "$T/err"))"
[ ! -s "$T/out" ] && [ ! -s "$T/calls" ] || fail "fill, an unrelated change: handed on [$(cat "$T/out")], calls [$(calls)]"
echo "pins-bot OK"
