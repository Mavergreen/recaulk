#!/bin/sh
# platform: macOS-only -- links and executes x86_64 Mach-O
# spec: src/backfills/cxxabi_pointer_catch.c and README "C++ exceptions" -- the pointer catch rules,
#       hidden in librecaulk.a (rule 1's declared exception) and public only in
#       librecaulk-cxxabi-exports.a, whose one consumer is libcxx22's libc++abi.1.dylib.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
EXP="$T/lib/librecaulk-cxxabi-exports.a"
VTS="__ZTVN10__cxxabiv119__pointer_type_infoE __ZTVN10__cxxabiv129__pointer_to_member_type_infoE"
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

x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
D="$(mktemp -d "${TMPDIR:-/tmp}/cxxabi-exports.XXXXXX")"
trap 'rm -rf "$D"' EXIT
# spec: README.md "C++ exceptions" -- the consumer's shape, a dylib that re-exports the system's
#       libc++abi and exports the two vtables, linked ahead of the re-export so they are its own.
set --
for vt in $VTS; do set -- "$@" "-Wl,-u,$vt"; echo "$vt"; done > "$D/exp"
/usr/bin/clang $FLAGS -arch x86_64 -dynamiclib -install_name @loader_path/libabi.dylib -o "$D/libabi.dylib" \
  "$@" "$EXP" -Wl,-reexport-lc++abi -Wl,-exported_symbols_list,"$D/exp" \
  || { echo "FAIL: a dylib exporting the two vtables from librecaulk-cxxabi-exports.a does not link"; exit 1; }
for vt in $VTS; do
  nm -gU "$D/libabi.dylib" | grep -q " $vt\$" || bad "the dylib does not export $vt"
done
. tests/helpers/cxx.sh
/usr/bin/clang++ $FLAGS -arch x86_64 $CXX_STD -o "$D/cxxabi" tests/cxx/cxxabi.cpp "$D/libabi.dylib" "$T/lib/librecaulk.a" \
  -framework CoreFoundation -framework Security -framework CoreServices -lobjc -lc++abi \
  || { echo "FAIL: the cxxabi checks do not link against the dylib"; exit 1; }
for vt in $VTS; do
  nm -m "$D/cxxabi" | grep -q "(undefined) external $vt (from libabi)" \
    || bad "the program does not take $vt from the dylib: $(nm -m "$D/cxxabi" | grep " $vt" | head -1)"
done
out="$("$D/cxxabi" 2>&1)" && rc=0 || rc=$?
[ "$rc" = 0 ] || { printf '%s\n' "$out" | grep -v '^PASS'; bad "cxxabi through the dylib exited $rc"; }
[ "$fail" = 0 ] && echo "cxxabi-exports OK"
exit $fail
