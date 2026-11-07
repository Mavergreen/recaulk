#!/bin/sh
# platform: host-agnostic -- builds the Recents decision checks for x86_64; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: tests/README.objc-workspace.md -- recording boundaries only; never edits shared history or preferences;
#       a copy whose zero-limit guard is broken must fail, so the disabled-preference assertion is effective
#   usage: objc-workspace-recent-decisions.sh [--mutation-check]
set -eu
umask 077
cd "$(dirname "$0")/.."
case "${1:-}" in
  '') [ "$#" = 0 ] || exit 2 ;;
  --mutation-check) [ "$#" = 1 ] || exit 2 ;;
  *) exit 2 ;;
esac
. tests/helpers/built.sh

if compiling; then
  M="$(dirname "$(tbin x)")/mutant-src"
  rm -rf "$M"; mkdir -p "$M"
  cp tests/c/objc_workspace_recent_decisions.m "$M/"
  awk '{sub(/if \(ok \&\& maximum > 0\)/,"if (ok)"); print}' tests/c/objc_workspace_note_recents.h > "$M/objc_workspace_note_recents.h"
  cmp -s tests/c/objc_workspace_note_recents.h "$M/objc_workspace_note_recents.h" \
    && { echo "FAIL: the mutation no longer applies to objc_workspace_note_recents.h"; exit 1; }
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations tests/c/objc_workspace_recent_decisions.m \
    -o "$(tbin decisions)" -framework AppKit -framework Carbon
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations "$M/objc_workspace_recent_decisions.m" \
    -o "$(tbin mutant)" -framework AppKit -framework Carbon
  check_loads "$(tbin decisions)" "$(tbin mutant)"
fi
runtime_half
if [ "${1:-}" = --mutation-check ]; then
  "$(tbin mutant)"
  exit
fi
"$(tbin decisions)"
rc=0; "$(tbin mutant)" > /dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || { echo "FAIL: a broken zero-limit guard still passed, so the disabled-preference check guards nothing"; exit 1; }
echo "objc-workspace-recent-decisions OK"
