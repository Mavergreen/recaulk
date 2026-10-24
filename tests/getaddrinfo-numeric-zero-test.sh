#!/bin/sh
# platform: macOS-only -- exercises the system resolver through Recaulk's header.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo 'SKIP: this host cannot run x86_64 programs'; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/getaddrinfo-zero.XXXXXX")"
trap 'rm -rf "$work"' EXIT
/usr/bin/clang $FLAGS -arch x86_64 -isystem "$T/include/recaulk" \
  tests/c/getaddrinfo_numeric_zero.c -o "$work/test"
"$work/test"
