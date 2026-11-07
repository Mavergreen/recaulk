#!/bin/sh
# platform: host-agnostic -- builds the options observer with clang22 for 10.9; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: tests/README.objc-workspace.md "Additional native option measurements (not provider acceptance)" --
#       a real split-print writer must not satisfy an incomplete observation; --mutation-check runs an
#       observer that returns after the first print callback, and expects exit 1
set -eu
case "${1:-}" in
  '') [ "$#" = 0 ] || exit 2; program=observation ;;
  --mutation-check) [ "$#" = 1 ] || exit 2; program=observation-mutated ;;
  *) exit 2 ;;
esac
cd "$(dirname "$0")/.."
. tests/helpers/built.sh

if compiling; then
  M="$(dirname "$(tbin x)")/mutated"
  rm -rf "$M"; mkdir "$M"
  cp tests/c/objc_workspace_options_observation.m tests/c/objc_workspace_reference.m "$M/"
  awk '/for \(NSURL \*url in urls\) ready &= contains/ { print "        ready &= contains(rs, @\"print\", nil);"; next } { print }' \
    tests/c/objc_workspace_options_reference.m > "$M/objc_workspace_options_reference.m"
  if cmp -s tests/c/objc_workspace_options_reference.m "$M/objc_workspace_options_reference.m"; then
    echo "FAIL: the mutation no longer applies to tests/c/objc_workspace_options_reference.m"; exit 1
  fi
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations tests/c/objc_workspace_options_observation.m \
    -o "$(tbin observation)" -framework AppKit -framework Carbon
  "$CC" $FLAGS -fno-objc-arc -Wno-deprecated-declarations "$M/objc_workspace_options_observation.m" \
    -o "$(tbin observation-mutated)" -framework AppKit -framework Carbon
  check_loads "$(tbin observation)" "$(tbin observation-mutated)"
fi
runtime_half
R="$(mktemp -d "${TMPDIR:-/tmp}/workspace-options-observation.XXXXXX")"
trap 'rm -rf "$R"' EXIT
"$(tbin "$program")" "$R"
