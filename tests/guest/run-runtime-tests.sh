#!/bin/sh
# platform: host-agnostic -- POSIX sh and perl 5, both on stock 10.9; the on-mavericks job runs it there
# spec: README.md "Tests" -- the runtime half of each runtime test (every tests/*.sh marked
#       (RECAULK_TEST_PHASE) on line 2 with a runtime_half line, or those named) against RECAULK_BUILD
#       and RECAULK_INSTALLED, the installed product, when set (its libraries must be the build tree's),
#       each under a bound (RECAULK_GUEST_TEST_BOUND, default 300 s) that kills it and all it started,
#       and all within a budget (RECAULK_GUEST_BUDGET, default 2700 s) past which the rest are named as
#       not run; a hang, a failure, a skip (77) and a test not run fail by name, and the script exits 1.
set -eu
cd "$(dirname "$0")/../.."
: "${RECAULK_BUILD:?set RECAULK_BUILD to the build tree the build phase made}"
bound="${RECAULK_GUEST_TEST_BOUND:-300}"
budget="${RECAULK_GUEST_BUDGET:-2700}"
if [ "$#" -eq 0 ]; then
  for t in tests/*.sh; do
    if sed -n 2p "$t" | grep -q '(RECAULK_TEST_PHASE)' && grep -q '^runtime_half$' "$t"; then
      set -- "$@" "$t"
    fi
  done
fi
[ "$#" -gt 0 ] || { echo "FAIL: no runtime tests found"; exit 1; }
if [ -n "${RECAULK_INSTALLED:-}" ]; then
  for f in librecaulk.a librecaulk-cxxabi-exports.a libRecaulkSystem.dylib; do
    cmp -s "$RECAULK_INSTALLED/lib/$f" "$RECAULK_BUILD/stage/usr/local/mavergreen/recaulk/lib/$f" \
      || { echo "FAIL: the installed $RECAULK_INSTALLED/lib/$f is not the build tree's, so the tests would not test it"; exit 1; }
  done
fi

hit="$(mktemp "${TMPDIR:-/tmp}/run-runtime-tests.XXXXXX")"   # template: 10.9 BSD mktemp requires one
trap 'rm -f "$hit"' EXIT
start="$(date +%s)"
failed=0
for t in "$@"; do
  if [ $(( $(date +%s) - start )) -ge "$budget" ]; then
    echo "FAIL $t (not run: the run's $budget s budget is spent)"
    failed=1
    continue
  fi
  # platform: no timeout(1) on 10.9; perl runs the test in its own process group, kills that group at the
  #           bound so a hung program the test started dies with it, and records in $hit that it did
  : > "$hit"
  rc=0
  RECAULK_TEST_PHASE=run perl -e '
    my ($bound, $hit) = (shift, shift);
    my $pid = fork;
    die "fork: $!" unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV or exit 127 }
    $SIG{ALRM} = sub {
      kill "KILL", -$pid; waitpid($pid, 0);
      my $f;
      open($f, ">", $hit) and print $f "outlived\n";
      exit 124;
    };
    alarm $bound;
    waitpid($pid, 0);
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$bound" "$hit" sh "$t" || rc=$?
  if [ -s "$hit" ]; then
    echo "FAIL $t (outlived $bound s)"; failed=1
  else
    case "$rc" in
      0) echo "ok $t" ;;
      77) echo "FAIL $t (skipped with 77; on 10.9 every runtime test must run)"; failed=1 ;;
      *) echo "FAIL $t (exited $rc)"; failed=1 ;;
    esac
  fi
done
exit "$failed"
