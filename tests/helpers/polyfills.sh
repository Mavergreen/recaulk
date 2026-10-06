#!/bin/sh
# platform: host-agnostic
polyfills_verdict() {
  _pv_out="$1"; _pv_rc="$2"; _pv_dev="$3"; _pv_fb="$4"
  _pv_fail=0
  _pv_bad() { echo "FAIL: $*"; _pv_fail=1; }
  _pv_ver="$(macos_version)" || _pv_ver=""
  case "$_pv_ver" in
    [0-9]*.[0-9]*) ;;
    *) echo "FAIL: cannot judge test_polyfills: sw_vers -productVersion printed '$_pv_ver'"; return 1 ;;
  esac
  _pv_d="$(mktemp -d "${TMPDIR:-/tmp}/polyfills-verdict.XXXXXX")"
  : > "$_pv_d/tolerated"; : > "$_pv_d/unjudged"; : > "$_pv_d/conds"
  for _pv_f in "$_pv_dev" "$_pv_fb"; do
    while IFS= read -r _pv_line; do
      _pv_era="$(printf '%s\n' "$_pv_line" | cut -f1)"
      _pv_cond="$(printf '%s\n' "$_pv_line" | cut -f2-)"
      case "$_pv_era" in
        "<"[0-9]*.[0-9]*) ;;
        *) _pv_bad "$_pv_f: want '<MAJOR.MINOR<TAB>condition', got: $_pv_line"; continue ;;
      esac
      [ -n "$_pv_cond" ] && [ "$_pv_cond" != "$_pv_line" ] \
        || { _pv_bad "$_pv_f: want '<MAJOR.MINOR<TAB>condition', got: $_pv_line"; continue; }
      printf '%s\n' "$_pv_cond" >> "$_pv_d/conds"
      if version_below "$_pv_ver" "${_pv_era#<}"; then
        [ "$_pv_f" = "$_pv_dev" ] && printf '%s\n' "$_pv_cond" >> "$_pv_d/tolerated"
      else
        [ "$_pv_f" = "$_pv_fb" ] && printf '%s\n' "$_pv_cond" >> "$_pv_d/unjudged"
      fi
    done < "$_pv_f"
  done

  sed -n 's/^  FAIL : \(.*\)  (errno=.*$/\1/p' "$_pv_out" > "$_pv_d/failed"
  while IFS= read -r _pv_cond; do
    if grep -Fx -- "$_pv_cond" "$_pv_d/tolerated" >/dev/null; then
      echo "tolerated known deviation on $_pv_ver, where MacPorts' implementation runs: $_pv_cond"
    elif grep -Fx -- "$_pv_cond" "$_pv_d/unjudged" >/dev/null; then
      echo "not judged on $_pv_ver, where the system's implementation runs: $_pv_cond (asserts the 10.9 fallback)"
    else
      _pv_bad "test_polyfills on $_pv_ver: unexpected failure: $_pv_cond"
    fi
  done < "$_pv_d/failed"

  while IFS= read -r _pv_cond; do
    if ! grep -Fx -- "  ok   : $_pv_cond" "$_pv_out" >/dev/null && ! grep -Fx -- "$_pv_cond" "$_pv_d/failed" >/dev/null; then
      _pv_bad "stale entry in $_pv_dev or $_pv_fb, not in test_polyfills' output: $_pv_cond"
    fi
  done < "$_pv_d/conds"
  while IFS= read -r _pv_cond; do
    if grep -Fx -- "  ok   : $_pv_cond" "$_pv_out" >/dev/null; then
      _pv_bad "MacPorts fixed it on $_pv_ver: remove the entry from $_pv_dev ($_pv_cond)"
    fi
  done < "$_pv_d/tolerated"

  [ "$_pv_rc" -lt 128 ] || _pv_bad "test_polyfills died with status $_pv_rc"
  if [ "$_pv_rc" != 0 ] && [ "$_pv_rc" -lt 128 ] && [ ! -s "$_pv_d/failed" ]; then
    _pv_bad "test_polyfills exited $_pv_rc with no FAIL line"
  fi
  rm -rf "$_pv_d"
  return $_pv_fail
}
