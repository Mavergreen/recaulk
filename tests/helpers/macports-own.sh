#!/bin/sh
# platform: host-agnostic
macports_own_verdict() {
  _mo_log="$1"; _mo_rc="$2"; _mo_rosetta="$3"; _mo_known="$4"
  _mo_fail=0
  _mo_bad() { echo "FAIL: $*"; _mo_fail=1; }
  _mo_d="$(mktemp -d "${TMPDIR:-/tmp}/macports-own-verdict.XXXXXX")"

  _mo_block() {
    awk -v t="tbin/$1" '
      $0 == t || $0 == t " " { inb = 1; seen = 1; next }
      inb && /^(\/|tbin\/|install |make)/ { inb = 0 }
      inb { print }
      END { exit !seen }' "$_mo_log"
  }

  sed -n 's/^make[^ ]*: \*\*\* \[\(.*\)\] Error [0-9]*$/\1/p' "$_mo_log" > "$_mo_d/errors"
  while IFS= read -r _mo_t; do
    case "$_mo_t" in
      *run_*) _mo_n="test_${_mo_t##*run_}" ;;
      *) _mo_bad "MacPorts' tests did not build: make failed on $_mo_t"; continue ;;
    esac
    if [ "$_mo_rosetta" = 1 ] && grep -Fx -- "$_mo_n" "$_mo_known" >/dev/null; then
      _mo_block "$_mo_n" > "$_mo_d/block" || : > "$_mo_d/block"
      if awk -v n="$_mo_n" '
          /^    SO_TIMESTAMP_MONOTONIC uint64_t \(mach\) value [0-9]+ is not between [0-9]+ and [0-9]+$/ && $5 + 0 < $9 + 0 { sig++; next }
          $0 == n " failed." { done++; next }
          { other++ }
          END { exit !(sig >= 1 && done == 1 && other == 0) }' "$_mo_d/block"; then
        echo "tolerated under Rosetta 2, which underreports SO_TIMESTAMP_MONOTONIC's mach time: $_mo_n"
      else
        _mo_bad "MacPorts' $_mo_n failed under Rosetta 2 with more than its SO_TIMESTAMP_MONOTONIC underreport:"
        sed 's/^/  /' "$_mo_d/block"
      fi
    else
      _mo_bad "MacPorts' $_mo_n failed"
    fi
  done < "$_mo_d/errors"

  if [ "$_mo_rosetta" = 1 ]; then
    while IFS= read -r _mo_n; do
      if ! _mo_block "$_mo_n" > "$_mo_d/block"; then
        _mo_bad "stale entry in $_mo_known: MacPorts' tests did not run $_mo_n"
      elif grep -Fx -- "$_mo_n passed." "$_mo_d/block" >/dev/null; then
        _mo_bad "$_mo_n passes under Rosetta 2 now: remove it from $_mo_known"
      fi
    done < "$_mo_known"
  fi

  if [ "$_mo_rc" != 0 ] && [ ! -s "$_mo_d/errors" ]; then
    _mo_bad "make exited $_mo_rc with no failed target"
  fi
  rm -rf "$_mo_d"
  return $_mo_fail
}
