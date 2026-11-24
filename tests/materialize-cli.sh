#!/bin/sh
# platform: host-agnostic
# spec: .superpowers/specs/2026-11-24-recaulk-materialize-design.md "Command line" -- usage, absolute paths, exit codes
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
[ "$fail" = 0 ] && echo "materialize-cli OK"
exit "$fail"
