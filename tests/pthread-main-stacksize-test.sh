#!/bin/sh
# platform: host-agnostic -- builds x86_64 programs (one with an LC_MAIN stacksize written in); runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Fixes to functions 10.9 has" -- the main thread's pthread_get_stacksize_np is the stack the kernel
#       gave it, page-rounded: round_page(RLIMIT_STACK's soft limit), under a limit that is not a page multiple
#       too, and round_page(stacksize) for a program whose LC_MAIN carries one (Apple ld's -stack_size), where
#       MacPorts 1.5.2 returned the limit as is; and all of it is usable
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
py="$(command -v python3 || command -v python)" || { echo "FAIL: no python to write the LC_MAIN stacksize"; exit 1; }
if compiling; then
  for v in static dylib; do
    if [ $v = static ]; then lib="$T/lib/librecaulk.a"; else lib="-L$T/lib -lRecaulkSystem"; fi
    "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror -I"$T/include/recaulk" tests/c/pthread_main_stacksize.c $lib -o "$(tbin $v)"
    # platform: lld has no -stack_size, so the 32 MiB + 1 byte LC_MAIN stacksize is written into a copy
    cp "$(tbin $v)" "$(tbin $v-stack)"
    "$py" tests/helpers/set-lc-main-stacksize.py "$(tbin $v-stack)" 33554433
    check_loads "$(tbin $v)" "$(tbin $v-stack)"
  done
fi
runtime_half
fail=0
for v in static dylib; do
  for kib in 8192 8190 16384 520; do
    out="$( (ulimit -s $kib && DYLD_LIBRARY_PATH="$T/lib" "$(tbin $v)") 2>&1)" || { echo "FAIL $v ulimit -s $kib: $out"; fail=1; continue; }
    echo "ok $v ulimit -s $kib: $(echo $out)"
  done
  out="$(DYLD_LIBRARY_PATH="$T/lib" "$(tbin $v-stack)" 2>&1)" || { echo "FAIL $v LC_MAIN stacksize: $out"; fail=1; continue; }
  case "$out" in *"kernel gave 33558528"*) echo "ok $v LC_MAIN stacksize: $(echo $out)" ;;
    *) echo "FAIL $v LC_MAIN stacksize: the kernel did not give round_page(32 MiB + 1): $out"; fail=1 ;; esac
done
[ "$fail" = 0 ] && echo "pthread-main-stacksize OK"
exit $fail
