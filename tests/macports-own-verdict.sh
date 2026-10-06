#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/macports-own.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/macports-own-verdict-test.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
known=tests/fixtures/macports-own-rosetta.txt
packets="packet packet_nocancel packet_nofix packet_nofix_nocancel"

{
  printf '%s\n' 'install -d -m 755 tbin' \
    '/usr/bin/clang -arch x86_64 tbin/test_arc4random.o lib/libMacportsLegacySupport.a -o tbin/test_arc4random_static' \
    'tbin/test_arc4random_static ' 'test_arc4random_static completed.'
  for p in $packets; do
    printf '%s\n' "/usr/bin/clang -arch x86_64 tbin/test_$p.o lib/libMacportsLegacySupport.a -o tbin/test_${p}_static" \
      "tbin/test_${p}_static " "test_${p}_static passed."
  done
} > "$D/native.log"

rosetta_log() {
  awk -v low="${1:-169739607416}" '
    /^test_packet[a-z_]*_static passed\.$/ {
      n = $1; t = n; sub(/^test_/, "run_", t)
      printf "    SO_TIMESTAMP_MONOTONIC uint64_t (mach) value 4073751689 is not between %s and 169739679166\n", low
      print n " failed."
      if (n == "test_packet_nofix_static") print "make: *** [Makefile:468: " t "] Error 1"
      else print "make: *** [" t "] Error 1"
      next
    }
    { print }
    END { print "make: Target `test_static'"'"' not remade because of errors." }' "$D/native.log"
}
rosetta_log > "$D/rosetta.log"

judge() {
  got="$(macports_own_verdict "$1" "$2" "$3" "$known" 2>&1)" && vrc=0 || vrc=$?
}
passes() {
  judge "$@"
  [ "$vrc" = 0 ] || bad "$1 (exit $2, Rosetta $3) should be accepted: $got"
}
fails_with() {
  want="$1"; shift
  judge "$@"
  [ "$vrc" != 0 ] || { bad "$1 (exit $2, Rosetta $3) should be rejected: $got"; return 0; }
  case "$got" in *"$want"*) ;; *) bad "$1 (exit $2, Rosetta $3) was rejected without '$want': $got" ;; esac
}

passes "$D/native.log" 0 0
passes "$D/rosetta.log" 2 1
for p in $packets; do
  case "$got" in *"tolerated under Rosetta 2, which underreports SO_TIMESTAMP_MONOTONIC's mach time: test_${p}_static"*) ;;
    *) bad "the Rosetta run does not report test_${p}_static as tolerated: $got" ;; esac
done

fails_with "MacPorts' test_packet_static failed" "$D/rosetta.log" 2 0
fails_with "test_packet_static passes under Rosetta 2 now" "$D/native.log" 0 1

awk '{ print } $0 == "tbin/test_packet_nocancel_static " { print "    Error on recvmsg: Bad file descriptor" }' "$D/rosetta.log" > "$D/extra-line.log"
fails_with "test_packet_nocancel_static failed under Rosetta 2 with more than" "$D/extra-line.log" 2 1

rosetta_log 1000 > "$D/over.log"
fails_with "failed under Rosetta 2 with more than" "$D/over.log" 2 1

sed 's/^test_arc4random_static completed\.$/test_arc4random_static failed./' "$D/rosetta.log" > "$D/other.log"
printf '%s\n' 'make: *** [run_arc4random_static] Error 1' >> "$D/other.log"
fails_with "MacPorts' test_arc4random_static failed" "$D/other.log" 2 1

awk '$0 == "tbin/test_packet_nofix_static " { skip = 1; next } skip && /^(\/|tbin\/|install |make)/ { skip = 0 } !skip' \
  "$D/rosetta.log" | grep -v 'run_packet_nofix_static' > "$D/stale.log"
fails_with "stale entry in $known: MacPorts' tests did not run test_packet_nofix_static" "$D/stale.log" 2 1

{ cat "$D/native.log"; printf '%s\n' 'make: *** [tbin/test_fmemopen.o] Error 1'; } > "$D/build.log"
fails_with "MacPorts' tests did not build: make failed on tbin/test_fmemopen.o" "$D/build.log" 2 0

fails_with "make exited 2 with no failed target" "$D/native.log" 2 0

[ "$fail" = 0 ] && echo "macports-own-verdict OK"
exit $fail
