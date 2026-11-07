#!/bin/sh
# platform: host-agnostic -- builds x86_64 Mach-O and reads it with nm; runs it on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macos.sh
. tests/helpers/polyfills.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/shim-tests.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

if compiling; then
  xcc="$CC $FLAGS -arch x86_64"
  STATIC_LIBS="-framework CoreFoundation -framework Security -framework CoreServices -lobjc"
  $xcc -isystem "$T/include/recaulk" -o "$(tbin test_polyfills)" tests/c/test_polyfills.c "$T/lib/librecaulk.a" $STATIC_LIBS \
    || { echo "FAIL: test_polyfills does not link plainly with librecaulk.a"; exit 1; }
  adapted() {
    $xcc -isystem "$T/include/recaulk" -o "$(tbin "$1")" "tests/c/$1.c" -L"$T/lib" -lRecaulkSystem \
      || { echo "FAIL: $1 does not link against libRecaulkSystem.dylib"; exit 1; }
    "$NM" -m "$(tbin "$1")" | grep "external $2 (from libRecaulkSystem)" >/dev/null \
      || bad "$1: an adapted binary must bind the override, not the re-exported libSystem's ($2)"
  }
  adapted kevent64_error_events _kevent64
  adapted dnssd_getaddrinfo_ex _DNSServiceGetAddrInfoEx
  $xcc -o "$(tbin ccrandom_zero)" tests/c/ccrandom_zero.c "$T/lib/librecaulk.a" \
    || { echo "FAIL: ccrandom_zero does not link plainly with librecaulk.a"; exit 1; }
  check_loads "$(tbin test_polyfills)" "$(tbin kevent64_error_events)" "$(tbin dnssd_getaddrinfo_ex)" "$(tbin ccrandom_zero)" || fail=1
  [ "$fail" = 0 ] || exit 1
fi
runtime_half

# platform: where the system has clonefile (10.12 and later), test_polyfills leaves its clone at /tmp/mls_clone_xyz
clone=/tmp/mls_clone_xyz
[ -e "$clone" ] && clone_was_there=1 || clone_was_there=0
"$(tbin test_polyfills)" > "$D/polyfills.out" 2>&1 && rc=0 || rc=$?
[ "$clone_was_there" = 1 ] || rm -f "$clone"
cat "$D/polyfills.out"
polyfills_verdict "$D/polyfills.out" "$rc" tests/fixtures/known-macports-deviations.txt tests/fixtures/fallback-only-checks.txt \
  || fail=1

# platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it is set where each test program is exec'd
out="$(DYLD_LIBRARY_PATH="$T/lib" "$(tbin kevent64_error_events)" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
[ "$rc" = 0 ] || bad "kevent64_error_events exited $rc"
case "$out" in *"kevent64_error_events: all passed"*) ;; *) bad "kevent64_error_events did not print 'all passed'" ;; esac

DYLD_LIBRARY_PATH="$T/lib" "$(tbin dnssd_getaddrinfo_ex)" || bad "dnssd_getaddrinfo_ex exited $?"

out="$("$(tbin ccrandom_zero)" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
{ [ "$rc" = 0 ] && [ "$out" = "ccrandom ok" ]; } || bad "CCRandomGenerateBytes with a zero-length request returns success, as Apple's does (spec, Product 1)"

[ "$fail" = 0 ] && echo "shim-tests OK"
exit $fail
