#!/bin/sh
# platform: macOS-only -- builds and executes x86_64 Mach-O
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
DRYDOCK="$B/drydock/drydock-macho-rewrite"
[ -x "$DRYDOCK" ] || { echo "FAIL: $DRYDOCK is not executable: sh build/build-lib.sh fetches it"; exit 1; }
D="$(mktemp -d "${TMPDIR:-/tmp}/fwd-floor.XXXXXX")"
trap 'rm -rf "$D"' EXIT

xcc() { /usr/bin/clang $FLAGS -arch x86_64 -Os "$@"; }
xcc -c tests/c/forward_floor_impl.c -o "$D/impl.o"
xcc -dynamiclib -install_name "$D/libmgsys.dylib" -o "$D/libmgsys.dylib" tests/c/forward_floor_sys.c
printf '%s\n' _mgfl_value > "$D/symbols"
sh build/rename-impls.sh "$DRYDOCK" "$D/symbols" "$D/impl.o"
SDK="$SDK" sh build/gen-trampolines.sh "$D/symbols" "$D/fwd"
{
  printf 'symbol rename _dlsym _mgfl_counting_dlsym\n'
  ! nm -u "$D/fwd/fwd-resolve.o" | grep -qx _sysctl || printf 'symbol rename _sysctl _mgfl_sysctl\n'
} | "$DRYDOCK" "$D/fwd/fwd-resolve.o" "$D/fwd/fwd-resolve.stand-ins.o" >/dev/null 2>&1 \
  || { echo "FAIL: could not point fwd-resolve.o's dlsym and sysctl at the stand-ins"; exit 1; }
mv -f "$D/fwd/fwd-resolve.stand-ins.o" "$D/fwd/fwd-resolve.o"
/usr/bin/libtool -static -o "$D/libfl.a" "$D/impl.o" "$D"/fwd/fwd-*.o
xcc -o "$D/impl-path" tests/c/forward_floor.c "$D/libfl.a"
xcc -o "$D/forward-path" tests/c/forward_floor.c "$D/libfl.a" "$D/libmgsys.dylib"

fail=0
# spec: build/forward-set.sh -- the forwarded set is what the 10.9 SDK does not export, so on 10.9
#       a lookup can only fail, and a failing dlsym allocates
check() {
  got="$(MGFL_OSRELEASE="$2" "$D/$1" 2>&1)" || { echo "FAIL: $1 on Darwin $2 exited non-zero: $got"; fail=1; return; }
  want="$(printf 'lookups %s\nvalue %s\nagain %s\n' "$3" "$4" "$4")"
  [ "$got" = "$want" ] && return
  echo "FAIL: $1 on Darwin $2 printed, against what it should:"
  printf '%s\n' "$got" > "$D/got"; printf '%s\n' "$want" > "$D/want"
  diff "$D/want" "$D/got" | sed 's/^/  /' || true
  [ "$2" != 13.4.0 ] || [ "$(sed -n 's/^lookups //p' "$D/got")" = 0 ] \
    || echo "FAIL: $1: on 10.9 a forwarded function looked itself up; from inside an allocator (upstream rustc's jemalloc locks with os_unfair_lock) dlsym's allocation re-enters it and crashes"
  fail=1
}
check impl-path 13.4.0 0 7
check forward-path 13.4.0 0 7
check impl-path 25.0.0 1 7
check forward-path 25.0.0 1 1007
[ "$fail" = 0 ] && echo "forward-floor OK"
exit $fail
