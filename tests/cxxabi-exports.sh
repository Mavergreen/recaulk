#!/bin/sh
# platform: host-agnostic -- links x86_64 Mach-O and reads it with nm; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: src/backfills/cxxabi_pointer_catch.c and README "C++ exceptions" -- the pointer catch rules,
#       hidden in librecaulk.a (a fix to a function 10.9 has; README) and public only in
#       librecaulk-cxxabi-exports.a, whose one consumer is libcxx22's libc++abi.1.dylib.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
EXP="$T/lib/librecaulk-cxxabi-exports.a"
VTS="__ZTVN10__cxxabiv119__pointer_type_infoE __ZTVN10__cxxabiv129__pointer_to_member_type_infoE"

if compiling; then
  [ -f "$EXP" ] || { echo "FAIL: $EXP missing"; exit 1; }
  # platform: nm -m names a hidden definition "private external", in 10.9's nm and in llvm-nm alike
  for vt in $VTS; do
    "${NM:-nm}" -gU -m "$T/lib/librecaulk.a" | grep -q "private external.* $vt\$" \
      || bad "librecaulk.a does not define $vt hidden"
  done
  got="$("${NM:-nm}" -gU -m "$EXP" | awk 'NF > 2 { print ($0 ~ / private external / ? "hidden" : "public"), $NF }' | LC_ALL=C sort | tr '\n' ' ')"
  want="public __ZTVN10__cxxabiv119__pointer_type_infoE public __ZTVN10__cxxabiv129__pointer_to_member_type_infoE "
  [ "$got" = "$want" ] || bad "librecaulk-cxxabi-exports.a defines '$got', want '$want'"
  [ "$fail" = 0 ] || exit 1

  D="$(mktemp -d "${TMPDIR:-/tmp}/cxxabi-exports.XXXXXX")"
  trap 'rm -rf "$D"' EXIT
  # spec: README.md "C++ exceptions" -- the consumer's shape, a dylib that re-exports the system's
  #       libc++abi and exports the two vtables, linked ahead of the re-export so they are its own.
  set --
  for vt in $VTS; do set -- "$@" "-Wl,-u,$vt"; echo "$vt"; done > "$D/exp"
  "$CC" $FLAGS -arch x86_64 -dynamiclib -install_name @loader_path/libabi.dylib -o "$(tbin libabi.dylib)" \
    "$@" "$EXP" -Wl,-reexport-lc++abi -Wl,-exported_symbols_list,"$D/exp" \
    || { echo "FAIL: a dylib exporting the two vtables from librecaulk-cxxabi-exports.a does not link"; exit 1; }
  for vt in $VTS; do
    "$NM" -gU "$(tbin libabi.dylib)" | grep -q " $vt\$" || bad "the dylib does not export $vt"
  done
  . tests/helpers/cxx.sh
  "$CXX" $FLAGS -arch x86_64 $CXX_STD -o "$(tbin cxxabi)" tests/cxx/cxxabi.cpp "$(tbin libabi.dylib)" "$T/lib/librecaulk.a" \
    -framework CoreFoundation -framework Security -framework CoreServices -lobjc -lc++abi \
    || { echo "FAIL: the cxxabi checks do not link against the dylib"; exit 1; }
  for vt in $VTS; do
    "$NM" -m "$(tbin cxxabi)" | grep -q "(undefined) external $vt (from libabi)" \
      || bad "the program does not take $vt from the dylib: $("$NM" -m "$(tbin cxxabi)" | grep " $vt" | head -1)"
  done
  check_loads "$(tbin cxxabi)" "$(tbin libabi.dylib)" || fail=1
  [ "$fail" = 0 ] || exit 1
fi
runtime_half
out="$("$(tbin cxxabi)" 2>&1)" && rc=0 || rc=$?
[ "$rc" = 0 ] || { printf '%s\n' "$out" | grep -v '^PASS'; bad "cxxabi through the dylib exited $rc"; }
[ "$fail" = 0 ] && echo "cxxabi-exports OK"
exit $fail
