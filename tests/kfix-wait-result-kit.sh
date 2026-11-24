#!/bin/sh
# platform: host-agnostic -- builds, with clang22, the kit that proves wait_result_prepost on a disposable 10.9.5 guest
# spec: README.md "The kernel-fixes kext" -- usage: sh tests/kfix-wait-result-kit.sh [OUT]. OUT/kfix-wr holds the
#       reproducer (tests/c/kfix_wait_result.c), RecaulkKernelFixes.kext built twice (kext-both: every fix;
#       kext-backstop: wait_result_prepost off, as the boot-arg would turn it off), run.sh and its README.md. It
##       loads nothing here; the guest runs it by hand, one boot per configuration, as its README.md says. With no OUT
#       it is a test: it builds the kit in a scratch directory, checks that it is whole, and removes it.
set -eu
cd "$(dirname "$0")/.."
if [ $# -eq 0 ]; then
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/kfix-wr-test.XXXXXX")"
  trap 'rm -rf "$SCRATCH"' EXIT
  sh "$0" "$SCRATCH" > "$SCRATCH.log" 2>&1 || { sed 's/^/    | /' "$SCRATCH.log"; rm -f "$SCRATCH.log"; echo "FAIL: the kit did not build"; exit 1; }
  rm -f "$SCRATCH.log"
  K="$SCRATCH/kfix-wr"
  for f in kfix_wait_result run.sh README.md COMMIT SHA256SUMS kext-both/RecaulkKernelFixes.kext kext-backstop/RecaulkKernelFixes.kext; do
    [ -e "$K/$f" ] || { echo "FAIL: the kit lacks $f"; exit 1; }
  done
  [ "$(wc -l < "$K/SHA256SUMS")" -ge 5 ] || { echo "FAIL: SHA256SUMS lists too few files"; exit 1; }
  echo "kfix-wait-result-kit OK"
  exit 0
fi
OUT="$1"
RECAULK_TEST_PHASE=build
. tests/helpers/built.sh
K="$OUT/kfix-wr"
rm -rf "$K"; mkdir -p "$K"
# spec: tests/kfix-runtime-test.sh -- a version above any release's
V=20991231.99
"$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror -O1 tests/c/kfix_wait_result.c -o "$K/kfix_wait_result"
check_loads "$K/kfix_wait_result"
for v in both backstop; do
  case "$v" in both) cf= ;; backstop) cf=-DRECAULK_KFIX_TEST_BACKSTOP_ONLY ;; esac
  VERSION=$V KEXT_SRC=src/kfix KEXT_NAME=RecaulkKernelFixes KEXT_CFLAGS="$cf" sh build/build-kext.sh "$K/build-$v" \
    > "$K/build-$v.log" 2>&1 || { echo "FAIL: the $v kext did not build:"; sed 's/^/    | /' "$K/build-$v.log"; exit 1; }
  mkdir -p "$K/kext-$v"
  cp -R "$K/build-$v/RecaulkKernelFixes.kext" "$K/kext-$v/"
  rm -rf "$K/build-$v" "$K/build-$v.log"
done
cp tests/kfix-wait-result/run.sh tests/kfix-wait-result/README.md "$K/"
git rev-parse HEAD > "$K/COMMIT" 2>/dev/null || echo unknown > "$K/COMMIT"
sha256() { if command -v sha256sum > /dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi; }
(cd "$K" && find . -type f ! -name SHA256SUMS | LC_ALL=C sort | while read -r f; do sha256 "$f"; done) > "$K/SHA256SUMS"
echo "kfix-wait-result-kit: $K"
