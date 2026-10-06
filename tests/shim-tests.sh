#!/bin/sh
# platform: macOS-only -- executes x86_64 Mach-O
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macos.sh
. tests/helpers/polyfills.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
D="$(mktemp -d "${TMPDIR:-/tmp}/shim-tests.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
CC="/usr/bin/clang $FLAGS -arch x86_64"
STATIC_LIBS="-framework CoreFoundation -framework Security -framework CoreServices -lobjc"

$CC -isystem "$T/include/recaulk" -o "$D/test_polyfills" tests/c/test_polyfills.c "$T/lib/librecaulk.a" $STATIC_LIBS \
  || { echo "FAIL: test_polyfills does not link plainly with librecaulk.a"; exit 1; }
# platform: where the system has clonefile (10.12 and later), test_polyfills leaves its clone at /tmp/mls_clone_xyz
clone=/tmp/mls_clone_xyz
[ -e "$clone" ] && clone_was_there=1 || clone_was_there=0
"$D/test_polyfills" > "$D/polyfills.out" 2>&1 && rc=0 || rc=$?
[ "$clone_was_there" = 1 ] || rm -f "$clone"
cat "$D/polyfills.out"
polyfills_verdict "$D/polyfills.out" "$rc" tests/fixtures/known-macports-deviations.txt tests/fixtures/fallback-only-checks.txt \
  || fail=1

# platform: SIP strips DYLD_* from protected binaries such as /bin/sh, so it is set where each test program is exec'd
adapted() {
  $CC -isystem "$T/include/recaulk" -o "$D/$1" "tests/c/$1.c" -L"$T/lib" -lRecaulkSystem \
    || { echo "FAIL: $1 does not link against libRecaulkSystem.dylib"; exit 1; }
  nm -m "$D/$1" | grep "external $2 (from libRecaulkSystem)" >/dev/null \
    || bad "$1: an adapted binary must bind the override, not the re-exported libSystem's ($2)"
}

adapted kevent64_error_events _kevent64
out="$(DYLD_LIBRARY_PATH="$T/lib" "$D/kevent64_error_events" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
[ "$rc" = 0 ] || bad "kevent64_error_events exited $rc"
case "$out" in *"kevent64_error_events: all passed"*) ;; *) bad "kevent64_error_events did not print 'all passed'" ;; esac

adapted dnssd_getaddrinfo_ex _DNSServiceGetAddrInfoEx
DYLD_LIBRARY_PATH="$T/lib" "$D/dnssd_getaddrinfo_ex" || bad "dnssd_getaddrinfo_ex exited $?"

$CC -o "$D/ccrandom_zero" tests/c/ccrandom_zero.c "$T/lib/librecaulk.a" \
  || { echo "FAIL: ccrandom_zero does not link plainly with librecaulk.a"; exit 1; }
out="$("$D/ccrandom_zero" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
{ [ "$rc" = 0 ] && [ "$out" = "ccrandom ok" ]; } || bad "CCRandomGenerateBytes with a zero-length request returns success, as Apple's does (spec, Product 1)"

[ "$fail" = 0 ] && echo "shim-tests OK"
exit $fail
