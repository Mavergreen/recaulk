#!/bin/sh
# platform: macOS-only -- builds and executes x86_64 Mach-O
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
DRYDOCK="$B/drydock/drydock-macho-rewrite"
[ -x "$DRYDOCK" ] || { echo "FAIL: $DRYDOCK is not executable: sh build/build-lib.sh fetches it"; exit 1; }
D="$(mktemp -d "${TMPDIR:-/tmp}/fwd-abi.XXXXXX")"
trap 'rm -rf "$D"' EXIT

xcc() { /usr/bin/clang $FLAGS -arch x86_64 -Os "$@"; }
xcc -c tests/c/forward_abi_impl.c -o "$D/impl.o"
xcc -dynamiclib -install_name "$D/libmgsys.dylib" -o "$D/libmgsys.dylib" tests/c/forward_abi_sys.c
printf '%s\n' _mgfwd_float _mgfwd_nop _mgfwd_varargs > "$D/symbols"
sh build/rename-impls.sh "$DRYDOCK" "$D/symbols" "$D/impl.o"
SDK="$SDK" sh build/gen-trampolines.sh "$D/symbols" "$D/fwd"
printf 'symbol rename _dlsym _mgfwd_clobbering_dlsym\n' \
  | "$DRYDOCK" "$D/fwd/fwd-resolve.o" "$D/fwd/fwd-resolve.clobbering.o" >/dev/null 2>&1 \
  || { echo "FAIL: could not point fwd-resolve.o's dlsym at the clobbering stand-in"; exit 1; }
mv -f "$D/fwd/fwd-resolve.clobbering.o" "$D/fwd/fwd-resolve.o"
/usr/bin/libtool -static -o "$D/libabi.a" "$D/impl.o" "$D"/fwd/fwd-*.o
xcc -o "$D/impl-path" tests/c/forward_abi.c "$D/libabi.a"
xcc -o "$D/forward-path" tests/c/forward_abi.c "$D/libabi.a" "$D/libmgsys.dylib"

fail=0
expect() {
  printf 'varargs %s\nvarargs %s\nvarargs-fp %s\nvarargs-fp %s\nfloat %s\nfloat %s\nregs 0\nregs 0\n' "$1" "$1" "$2" "$2" "$3" "$3"
}
check() {
  got="$("$D/$1" 2>&1)" || { echo "FAIL: the $1 binary exited non-zero: $got"; fail=1; return; }
  want="$(expect "$2" "$3" "$4")"
  [ "$got" = "$want" ] && return
  echo "FAIL: the $1 binary printed, against what it should:"
  printf '%s\n' "$got" > "$D/got"; printf '%s\n' "$want" > "$D/want"
  diff "$D/want" "$D/got" | sed 's/^/  /' || true
  if [ "$(grep '^float' "$D/got")" != "$(grep '^float' "$D/want")" ]; then
    echo "FAIL: $1: mgfwd_float's ten floating and integer arguments, one on the stack, arrived wrong: the trampoline lost xmm registers or its frame"
  fi
  if [ "$(grep '^varargs-fp' "$D/got")" != "$(grep '^varargs-fp' "$D/want")" ] \
    && [ "$(grep '^float' "$D/got")" = "$(grep '^float' "$D/want")" ]; then
    echo "FAIL: $1: a variadic call with double arguments came out wrong though fixed xmm arguments did not: the trampoline lost al"
  fi
  for r in $(sed -n 's/^regs //p' "$D/got" | sort -u); do
    [ "$r" = 0 ] && continue
    lost=""
    [ $((r & 1)) = 0 ] || lost="$lost r10"
    [ $((r & 2)) = 0 ] || lost="$lost r11"
    [ $((r & 4)) = 0 ] || lost="$lost xmm8"
    [ $((r & 8)) = 0 ] || lost="$lost xmm15"
    echo "FAIL: $1: a caller's live$lost did not survive a call through the trampoline (a caller relying on more than the C ABI keeps them live)"
  done
  if [ "$(grep '^varargs ' "$D/got")" != "$(grep '^varargs ' "$D/want")" ]; then
    echo "FAIL: $1: mgfwd_varargs's six integer arguments arrived wrong: the trampoline lost the integer registers"
  fi
  fail=1
}
check impl-path 15 7 410.5
check forward-path 1015 1007 1410.5
[ "$fail" = 0 ] && echo "forward-abi OK"
exit $fail
