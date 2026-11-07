#!/bin/sh
# platform: host-agnostic -- builds x86_64 Mach-O and reads the dylib with nm; runs it on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macos.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/fwd-runtime.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

judge() {
  [ "$2" = 0 ] || { bad "$1: clock_gettime(CLOCK_REALTIME) returned $2"; return; }
  case "$era" in
    system)
      case "$3" in
        /usr/lib/*) echo "$1: on $ver clock_gettime forwarded to $3" ;;
        *) bad "$1: on $ver clock_gettime ran $3, not the system's: a back-fill must defer to the system's implementation when it exists (spec, Product 1)" ;;
      esac ;;
    10.9)
      [ "$3" = "$4" ] || { bad "$1: on $ver clock_gettime resolved to $3, want the renamed implementation in $4"; return; }
      echo "$1: on $ver clock_gettime ran the renamed implementation in $4" ;;
    *) echo "$1: on $ver clock_gettime ran $3 (no assertion between 10.9 and 10.12)" ;;
  esac
}
field() { printf '%s\n' "$1" | sed -n "s/^$2: //p"; }

dylib="$T/lib/libRecaulkSystem.dylib"
if compiling; then
  "$CC" $FLAGS -arch x86_64 -isystem "$T/include/recaulk" -o "$(tbin fwd)" tests/c/forward_runtime.c \
    "$T/lib/librecaulk.a" -framework CoreFoundation -framework Security -framework CoreServices -lobjc \
    || { echo "FAIL: a program calling clock_gettime does not link plainly with librecaulk.a"; exit 1; }
  slot="$("$NM" "$dylib" | awk '$3 == "___recaulk_slot_clock_gettime" { print $1 }')"
  [ -n "$slot" ] || { echo "FAIL: $dylib has no ___recaulk_slot_clock_gettime in its symbol table"; exit 1; }
  echo "$slot" > "$(tbin slot)"
  "$CC" $FLAGS -arch x86_64 -isystem "$T/include/recaulk" -o "$(tbin fwd-dylib)" tests/c/forward_runtime_dylib.c \
    -L"$T/lib" -lRecaulkSystem \
    || { echo "FAIL: a program calling clock_gettime does not link against libRecaulkSystem.dylib"; exit 1; }
  check_loads "$(tbin fwd)" "$(tbin fwd-dylib)"
fi
runtime_half
ver="$(macos_version)"
if ! version_below "$ver" 10.12; then
  era=system
elif version_below "$ver" 10.10 && ! version_below "$ver" 10.9; then
  era=10.9
else
  era=between
fi

out="$("$(tbin fwd)")" || { echo "FAIL: the librecaulk.a program exited non-zero: $out"; exit 1; }
judge librecaulk.a "$(field "$out" rc)" "$(field "$out" target)" "$(field "$out" self)"

# platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it must be set where the
#           test program is exec'd.
out="$(DYLD_LIBRARY_PATH="$T/lib" "$(tbin fwd-dylib)" "0x$(cat "$(tbin slot)")")" || { echo "FAIL: the libRecaulkSystem.dylib program exited non-zero: $out"; exit 1; }
loaded="$(field "$out" dylib)"
[ "$loaded" = "$dylib" ] || { echo "FAIL: the libRecaulkSystem.dylib program loaded $loaded, not the built copy $dylib"; exit 1; }
judge libRecaulkSystem.dylib "$(field "$out" rc)" "$(field "$out" target)" "$loaded"

[ "$fail" = 0 ] && echo "forward-runtime OK"
exit $fail
