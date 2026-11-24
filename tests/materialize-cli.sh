#!/bin/sh
# platform: host-agnostic
# spec: README.md "Materializing an SDK view" "Command line" -- usage, absolute paths, exit codes
set -eu
cd "$(dirname "$0")/.."
d="$(mktemp -d "${TMPDIR:-/tmp}/materialize-cli.XXXXXX")"
trap 'rm -rf "$d"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
sh build/build-materialize.sh host "$d/rm"
run() { "$d/rm" "$@" >"$d/out" 2>"$d/err" && rc=0 || rc=$?; }

echo "== version"
run --version
[ "$rc" = 0 ] || bad "--version exited $rc"
[ "$(wc -l <"$d/out" | tr -d ' ')" = 1 ] && grep -Eq '^recaulk-materialize [0-9a-z.]+$' "$d/out" \
  || bad "--version printed: $(cat "$d/out")"

echo "== usage"
run
[ "$rc" = 2 ] || bad "no arguments exited $rc, want 2"
grep -q '^recaulk-materialize: usage:' "$d/err" || bad "no arguments: stderr $(cat "$d/err")"

echo "== relative_path"
run --sdk rel --out /x --profile p
[ "$rc" = 2 ] || bad "relative --sdk exited $rc, want 2"
grep -q "rel" "$d/err" && grep -q absolute "$d/err" || bad "relative --sdk: stderr $(cat "$d/err")"

echo "== profile_and_recipe"
run --sdk /s --out /x --profile p --recipe a
[ "$rc" = 2 ] || bad "--profile with --recipe exited $rc, want 2"

echo "== print_stamp_needs_selection"
run --print-stamp
[ "$rc" = 2 ] || bad "--print-stamp alone exited $rc, want 2"

echo "== unknown_flag"
run --frob
[ "$rc" = 2 ] || bad "--frob exited $rc, want 2"
grep -q -- --frob "$d/err" || bad "--frob: stderr $(cat "$d/err")"

echo "== one_stderr_line"
[ "$(wc -l <"$d/err" | tr -d ' ')" = 1 ] || bad "a usage error printed more than one line"
echo "== from_path (review I2)"
mkdir -p "$d/p/bin" "$d/p/share/sdk-metadata"
cp "$d/rm" "$d/p/bin/recaulk-materialize"
cp tests/fixtures/materialize/recipes.json tests/fixtures/materialize/profiles.json "$d/p/share/sdk-metadata/"
mkdir "$d/elsewhere"
(cd "$d/elsewhere" && PATH="$d/p/bin:$PATH" recaulk-materialize --print-stamp --profile t) >"$d/out" 2>"$d/err" && rc=0 || rc=$?
[ "$rc" = 0 ] || bad "run from PATH it exited $rc: $(cat "$d/err")"
ln -s "$d/p/bin/recaulk-materialize" "$d/linked"
"$d/linked" --print-stamp --profile t >/dev/null 2>"$d/err" || bad "run through a symlink it failed: $(cat "$d/err")"

echo "== builds_with_gcc"
# platform: Linux builds with gcc, whose -Wformat-truncation clang lacks; MZ_GCC names one here
#           (pkgsrc's /opt/pkg/gcc14/bin/gcc on the 10.9 box), else a gcc on PATH that is really GCC
g="${MZ_GCC:-}"
[ -n "$g" ] || { command -v gcc >/dev/null 2>&1 && gcc --version 2>/dev/null | grep -q 'Free Software' && g=gcc; } || true
if [ -n "$g" ]; then
  for f in src/materialize/*.c; do
    "$g" -std=c99 -O2 -Wall -Wextra -Werror -D_XOPEN_SOURCE=700 -D_DARWIN_C_SOURCE -c "$f" -o "$d/gcc.o" 2>"$d/gcc.err" \
      || bad "$g refuses $f: $(grep -m1 error: "$d/gcc.err")"
  done
else
  echo "   (no GCC here; set MZ_GCC to check)"
fi

[ "$fail" = 0 ] && echo "materialize-cli OK"
exit "$fail"
