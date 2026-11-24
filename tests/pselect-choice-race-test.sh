#!/bin/sh
# platform: host-agnostic -- builds a librecaulk.a x86_64 program; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Waiting with pselect" -- a wait a watched signal wakes stays one the signal can be delivered
#       to while xnu picks its thread; tests/c/pselect_choice_race.c replays that order. librecaulk.a only: its
#       select and kevent bind by name, so the program can stand in for them; the dylib's are bound to libSystem.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Wextra -Werror tests/c/pselect_choice_race.c "$T/lib/librecaulk.a" -o "$(tbin static)"
  check_loads "$(tbin static)"
fi
runtime_half
out="$("$(tbin static)" 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out" | grep -v '^ok ' || :
[ "$rc" = 0 ] || { echo "FAIL: pselect-choice-race exited $rc"; exit 1; }
echo "pselect-choice-race OK"
