#!/bin/sh
# platform: host-agnostic -- builds MacPorts' static x86_64 tests with make; runs them on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macports-own.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/macports-own.XXXXXX")"
trap 'rm -rf "$D"' EXIT
if compiling; then
  mp="$W/macports-legacy-support-$(macports_version)"
  "$MAKE" -k -C "$mp" -f Makefile -f "$PWD/tests/helpers/macports-own.mk" CC="$CC" ARCHS=x86_64 TESTARCHS=x86_64 \
    CFLAGS="$FLAGS" LDFLAGS="$FLAGS" recaulk_static_progs > "$D/make.log" 2>&1 && rc=0 || rc=$?
  cat "$D/make.log"
  macports_own_verdict "$D/make.log" "$rc" || exit 1
  "$MAKE" -s TESTARCHS=x86_64 -C "$mp" -f Makefile -f "$PWD/tests/helpers/macports-own.mk" recaulk_list_static > "$(tbin progs)"
  [ -s "$(tbin progs)" ] || { echo "FAIL: MacPorts' Makefile lists no static test programs"; exit 1; }
  basename "$mp" > "$(tbin tree)"
  set --
  while IFS= read -r p; do set -- "$@" "$mp/$p"; done < "$(tbin progs)"
  check_loads "$@"
fi
runtime_half
# spec: tests/helpers/macports-own.mk -- MacPorts' run rule, "$< $(TEST_ARGS)" from its tree with
#       tst_data present, logged in make's shape
mp="$W/$(cat "$(tbin tree)")"
mkdir -p "$mp/tst_data"
rc=0
while IFS= read -r p; do
  echo "$p "
  (cd "$mp" && "./$p" < /dev/null) && prc=0 || prc=$?
  if [ "$prc" != 0 ]; then
    n="${p##*/test_}"
    echo "make: *** [run_$n] Error $prc"
    rc=2
  fi
done < "$(tbin progs)" > "$D/run.log" 2>&1
cat "$D/run.log"
macports_own_verdict "$D/run.log" "$rc" || exit 1
echo "macports-own OK ($(wc -l < "$(tbin progs)" | tr -d ' ') programs)"
