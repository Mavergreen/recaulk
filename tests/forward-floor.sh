#!/bin/sh
# platform: host-agnostic -- builds x86_64 Mach-O with drydock and the forwarding generator; runs it on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/fwd-floor.XXXXXX")"
trap 'rm -rf "$D"' EXIT

if compiling; then
  DRYDOCK="$B/drydock/drydock-macho-rewrite"
  [ -x "$DRYDOCK" ] || { echo "FAIL: $DRYDOCK is not executable: sh build/build-lib.sh fetches it"; exit 1; }
  xcc() { "$CC" $FLAGS -arch x86_64 -Os "$@"; }
  xcc -c tests/c/forward_floor_impl.c -o "$D/impl.o"
  xcc -dynamiclib -install_name @executable_path/libmgsys.dylib -o "$(tbin libmgsys.dylib)" tests/c/forward_floor_sys.c
  printf '%s\n' _mgfl_value > "$D/symbols"
  sh build/rename-impls.sh "$DRYDOCK" "$D/symbols" "$D/impl.o"
  SDK="$SDK" sh build/gen-trampolines.sh "$D/symbols" "$D/fwd"
  {
    printf 'symbol rename _dlsym _mgfl_counting_dlsym\n'
    printf 'symbol rename _NSVersionOfRunTimeLibrary _mgfl_nsversion\n'
  } | "$DRYDOCK" "$D/fwd/fwd-resolve.o" "$D/fwd/fwd-resolve.stand-ins.o" >/dev/null 2>&1 \
    || { echo "FAIL: could not point fwd-resolve.o's dlsym and NSVersionOfRunTimeLibrary at the stand-ins"; exit 1; }
  # spec: src/xnu_version.h -- a sysctl here would be a request a (deny default) sandbox denies
  if "$NM" -u "$D/fwd/fwd-resolve.o" | grep -qx -e _sysctl -e _sysctlbyname; then
    echo "FAIL: fwd-resolve.o asks the kernel its version with a sysctl"; exit 1
  fi
  mv -f "$D/fwd/fwd-resolve.stand-ins.o" "$D/fwd/fwd-resolve.o"
  recaulk_archive "$D/libfl.a" "$D/impl.o" "$D"/fwd/fwd-*.o
  xcc -o "$(tbin impl-path)" tests/c/forward_floor.c "$D/libfl.a"
  xcc -o "$(tbin forward-path)" tests/c/forward_floor.c "$D/libfl.a" "$(tbin libmgsys.dylib)"
  check_loads "$(tbin impl-path)" "$(tbin forward-path)" "$(tbin libmgsys.dylib)"
fi
runtime_half
fail=0
# spec: build/forward-set.sh -- the forwarded set is what the 10.9 SDK does not export, so on 10.9
#       a lookup can only fail, and a failing dlsym allocates
check() {
  got="$(MGFL_XNU="$2" "$(tbin "$1")" 2>&1)" || { echo "FAIL: $1 on xnu-$2 exited non-zero: $got"; fail=1; return; }
  want="$(printf 'lookups %s\nvalue %s\nagain %s\n' "$3" "$4" "$4")"
  [ "$got" = "$want" ] && return
  echo "FAIL: $1 on xnu-$2 printed, against what it should:"
  printf '%s\n' "$got" > "$D/got"; printf '%s\n' "$want" > "$D/want"
  diff "$D/want" "$D/got" | sed 's/^/  /' || true
  [ "$2" != 2422 ] || [ "$(sed -n 's/^lookups //p' "$D/got")" = 0 ] \
    || echo "FAIL: $1: on 10.9 a forwarded function looked itself up; from inside an allocator (upstream rustc's jemalloc locks with os_unfair_lock) dlsym's allocation re-enters it and crashes"
  fail=1
}
check impl-path 2422 0 7
check forward-path 2422 0 7
check impl-path 12377 1 7
check forward-path 12377 1 1007
[ "$fail" = 0 ] && echo "forward-floor OK"
exit $fail
