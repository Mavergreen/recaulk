#!/bin/sh
# platform: host-agnostic
# spec: PROVENANCE.md "MacPorts' own tests on 10.9" -- macports_own_verdict LOG RC judges a run logged
#       in make's shape (a failed target as "make: *** [<target>] Error N"); every failure fails.
macports_own_verdict() {
  _mo_log="$1"; _mo_rc="$2"
  _mo_fail=0
  _mo_bad() { echo "FAIL: $*"; _mo_fail=1; }
  _mo_d="$(mktemp -d "${TMPDIR:-/tmp}/macports-own-verdict.XXXXXX")"

  sed -n 's/^make[^ ]*: \*\*\* \[\(.*\)\] Error [0-9]*$/\1/p' "$_mo_log" > "$_mo_d/errors"
  while IFS= read -r _mo_t; do
    case "$_mo_t" in
      *run_*) _mo_bad "MacPorts' test_${_mo_t##*run_} failed" ;;
      *) _mo_bad "MacPorts' tests did not build: make failed on $_mo_t" ;;
    esac
  done < "$_mo_d/errors"

  if [ "$_mo_rc" != 0 ] && [ ! -s "$_mo_d/errors" ]; then
    _mo_bad "make exited $_mo_rc with no failed target"
  fi
  rm -rf "$_mo_d"
  return $_mo_fail
}
