#!/bin/sh
# platform: macOS-only -- sw_vers reports the running macOS
macos_version() {
  sw_vers -productVersion
}

version_below() {
  _vb_a="${1%%.*}"
  _vb_b="$(printf '%s\n' "$1" | sed -n 's/^[0-9]*\.\([0-9]*\).*$/\1/p')"
  _vb_x="${2%%.*}"
  _vb_y="$(printf '%s\n' "$2" | sed -n 's/^[0-9]*\.\([0-9]*\).*$/\1/p')"
  [ "$_vb_a" -lt "$_vb_x" ] || { [ "$_vb_a" = "$_vb_x" ] && [ "${_vb_b:-0}" -lt "${_vb_y:-0}" ]; }
}

plist_buddy() { /usr/libexec/PlistBuddy "$@"; }
plist_util() { /usr/bin/plutil "$@"; }
# platform: 10.9 launches an unsigned app, and its codesign needs the Command Line Tools' codesign_allocate,
#           which stock 10.9 lacks, so a fixture's ad-hoc signature is made only on 10.10 and later
code_sign() {
  if version_below "$(macos_version)" 10.10; then return 0; fi
  /usr/bin/codesign "$@"
}
