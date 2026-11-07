#!/bin/sh
# platform: host-agnostic -- links x86_64 Mach-O against librecaulk.a and reads it with nm; runs it on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macos.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/os-system-version.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
field() { printf '%s\n' "$1" | sed -n "s/^$2: //p"; }
libs="-framework CoreFoundation -framework Security -framework CoreServices -lobjc"

if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" -o "$(tbin osv)" tests/c/os_system_version.c \
    "$T/lib/librecaulk.a" $libs \
    || { echo "FAIL: a program that includes <os/system_version.h> and calls os_system_version_get_current_version does not compile and link plainly with librecaulk.a"; exit 1; }
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" -o "$(tbin osv-impl)" tests/c/os_system_version_impl.c \
    "$T/lib/librecaulk.a" $libs \
    || { echo "FAIL: the os_system_version back-fill's seam does not link from librecaulk.a"; exit 1; }
  check_loads "$(tbin osv)" "$(tbin osv-impl)"
  "$NM" -m "$T/lib/librecaulk.a" > "$D/archive.nm" || { echo "FAIL: nm -m could not read librecaulk.a"; exit 1; }
  seam="$(awk '$NF == "___recaulk_os_system_version_read"' "$D/archive.nm")"
  case "$seam" in
    *"private external"*) ;;
    *) bad "librecaulk.a's ___recaulk_os_system_version_read is not private external, so a consumer would export the test seam: ${seam:-(absent)}" ;;
  esac
  dylib="$T/lib/libRecaulkSystem.dylib"
  "$NM" -gU "$dylib" > "$D/dylib.nm" || { echo "FAIL: nm -gU could not read $dylib"; exit 1; }
  awk '{ print $NF }' "$D/dylib.nm" | grep -qx _os_system_version_get_current_version \
    || bad "libRecaulkSystem.dylib does not export _os_system_version_get_current_version"
  if awk '{ print $NF }' "$D/dylib.nm" | grep -q '^___recaulk_os_system_version'; then
    bad "libRecaulkSystem.dylib exports the os_system_version test seam"
  fi
  [ "$fail" = 0 ] || exit 1
fi
runtime_half
ver="$(macos_version)"
case "$ver" in
  *.*.*) ver3="$ver" ;;
  *) ver3="$ver.0" ;;
esac
if ! version_below "$ver" 10.12; then
  era=system
elif version_below "$ver" 10.10 && ! version_below "$ver" 10.9; then
  era=10.9
else
  era=between
fi

out="$("$(tbin osv)")" || { echo "FAIL: the os_system_version program exited non-zero: $out"; exit 1; }
printf '%s\n' "$out"
rc="$(field "$out" rc)"
got="$(field "$out" version)"
target="$(field "$out" target)"
self="$(field "$out" self)"
[ "$rc" = 0 ] || bad "os_system_version_get_current_version returned $rc on $ver, want 0, as Apple's does on success"
case "$era" in
  10.9)
    [ "$got" = "$ver3" ] || bad "on $ver os_system_version_get_current_version reported $got, want $ver3 (sw_vers)"
    [ "$target" = "$self" ] || bad "on $ver os_system_version_get_current_version resolved to $target, want the back-fill in $self" ;;
  system)
    case "$target" in
      /usr/lib/*) echo "on $ver os_system_version_get_current_version forwarded to $target and reported $got" ;;
      *) bad "on $ver os_system_version_get_current_version ran $target, not the system's: a back-fill must defer to the system's implementation when it exists (spec, Product 1)" ;;
    esac ;;
  *) echo "on $ver os_system_version_get_current_version ran $target and reported $got (no assertion between 10.9 and 10.12)" ;;
esac

want=-
[ "$era" != 10.9 ] || want="$ver3"
out="$("$(tbin osv-impl)" tests/fixtures/SystemVersion-10.9.5.plist "$want" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out"
case "$out" in
  *"os_system_version_impl: all passed"*) [ "$rc" = 0 ] || bad "os_system_version_impl exited $rc after passing" ;;
  *) bad "the 10.9 os_system_version_get_current_version does not report as Apple's does: 0 and the version, or an errno and the version untouched (PROVENANCE.md, os_system_version_get_current_version), exit $rc" ;;
esac

[ "$fail" = 0 ] && echo "os-system-version OK"
exit $fail
