#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/macports-own.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/macports-own-verdict-test.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
packets="packet packet_nocancel packet_nofix packet_nofix_nocancel"

{
  printf '%s\n' 'tbin/test_arc4random_static ' 'test_arc4random_static completed.'
  for p in $packets; do
    printf '%s\n' "tbin/test_${p}_static " "test_${p}_static passed."
  done
} > "$D/pass.log"

judge() {
  got="$(macports_own_verdict "$1" "$2" 2>&1)" && vrc=0 || vrc=$?
}
passes() {
  judge "$@"
  [ "$vrc" = 0 ] || bad "$1 (exit $2) should be accepted: $got"
}
fails_with() {
  want="$1"; shift
  judge "$@"
  [ "$vrc" != 0 ] || { bad "$1 (exit $2) should be rejected: $got"; return 0; }
  case "$got" in *"$want"*) ;; *) bad "$1 (exit $2) was rejected without '$want': $got" ;; esac
}

passes "$D/pass.log" 0

# spec: PROVENANCE.md "MacPorts' own tests on 10.9" -- every failure is a finding: the
#       SO_TIMESTAMP_MONOTONIC underreport once allowed under Rosetta now fails like any other
awk '$0 == "test_packet_static passed." {
       print "    SO_TIMESTAMP_MONOTONIC uint64_t (mach) value 4073751689 is not between 169739607416 and 169739679166"
       print "test_packet_static failed."; print "make: *** [run_packet_static] Error 1"; next }
     { print }' "$D/pass.log" > "$D/packet.log"
fails_with "MacPorts' test_packet_static failed" "$D/packet.log" 2

{ cat "$D/pass.log"; printf '%s\n' 'make: *** [Makefile:468: run_arc4random_static] Error 1'; } > "$D/located.log"
fails_with "MacPorts' test_arc4random_static failed" "$D/located.log" 2

{ cat "$D/pass.log"; printf '%s\n' 'make: *** [tbin/test_fmemopen.o] Error 1'; } > "$D/build.log"
fails_with "MacPorts' tests did not build: make failed on tbin/test_fmemopen.o" "$D/build.log" 2

fails_with "make exited 2 with no failed target" "$D/pass.log" 2

[ "$fail" = 0 ] && echo "macports-own-verdict OK"
exit $fail
