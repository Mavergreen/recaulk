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
