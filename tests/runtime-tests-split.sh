#!/bin/sh
# platform: host-agnostic -- reads the test scripts as text
# spec: README.md "Tests" -- a runtime test builds on the runner and runs on 10.9: no test probes for
#       or relies on Rosetta; a test that builds programs keeps them in tbin and has a runtime_half
#       line; before runtime_half a built program is only compiled or read, never run.
set -eu
cd "$(dirname "$0")/.."
fail=0
bad() { echo "FAIL: $*"; fail=1; }
self=tests/runtime-tests-split.sh

for f in tests/*.sh tests/helpers/*.sh tests/guest/*.sh; do
  [ "$f" != "$self" ] || continue
  if grep -n -i -E 'x86_64_runs|arch -x86_64|install-rosetta|hw\.optional\.arm64|[_-]rosetta|rosetta[=_]' "$f" > /dev/null; then
    bad "$f relies on Rosetta or probes for it: $(grep -n -i -E 'x86_64_runs|arch -x86_64|install-rosetta|hw\.optional\.arm64|[_-]rosetta|rosetta[=_]' "$f" | head -1)"
  fi
done

for f in tests/*.sh; do
  # spec: tests/test-phases.sh -- its fake runtime tests live in heredocs; it is not one itself
  case "$f" in "$self"|tests/test-phases.sh) continue ;; esac
  grep -q '"$(tbin ' "$f" || continue
  grep -q '^runtime_half$' "$f" || bad "$f builds programs into tbin but has no runtime_half line"
  # spec: tests/guest/run-runtime-tests.sh -- it takes the tests marked on line 2, so none goes unrun
  sed -n 2p "$f" | grep -q '(RECAULK_TEST_PHASE)' \
    || bad "$f builds programs into tbin but line 2 lacks (RECAULK_TEST_PHASE), so the guest would not run it"
  # spec: README.md "Tests" -- a program built in a scratch directory never reaches the guest; an
  #       object (-c, .o) or archive (.a) is an intermediate, never run, so it may stay there
  grep -n -E -- ' -o "\$(D|work|tmp)/' "$f" | grep -v -e ' -c ' | grep -v -E '\.(o|a)"' | while IFS= read -r l; do
    echo "FAIL: $f builds into a scratch directory, not tbin: $l"
  done
  awk -v f="$f" '
    /^runtime_half$/ { exit }
    {
      # spec: README.md "Tests" -- a built program in command position: at the start of a line or a
      #       command substitution, or after ; && || then do, past any VAR=value prefixes
      if ($0 ~ /(^|\$\(|;|&&|\|\||then|do)[ \t]*([A-Za-z_][A-Za-z0-9_]*="[^"]*"[ \t]+)*"\$\(tbin /)
        print "FAIL: " f ":" NR " runs a built program before runtime_half: " $0
    }' "$f"
done | { out="$(cat)"; [ -z "$out" ] || { printf '%s\n' "$out"; exit 1; }; } || fail=1

[ "$fail" = 0 ] && echo "runtime tests split OK"
exit "$fail"
