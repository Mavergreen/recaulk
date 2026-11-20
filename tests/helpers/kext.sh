#!/bin/sh
# platform: host-agnostic -- builds RecaulkKPI.kext's objects and Info.plist into a scratch directory
# spec: README.md "The kernel back-fill kext" -- what the kext tests share
py="$(command -v python3 || command -v python)" || { echo "FAIL: no python3 or python to read Info.plist"; exit 1; }
plist() { "$py" tests/helpers/plist.py "$@"; }
kext_build() { # kext_build OUT [VERSION]
  VERSION="${2:-20261120.1}" sh build/build-kext.sh "$1" > "$1.log" 2>&1 \
    || { echo "FAIL: build/build-kext.sh failed:"; sed 's/^/    | /' "$1.log"; exit 1; }
}
