#!/bin/sh
# platform: macOS-only -- combines native kqueue with UDP packet readiness.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo 'SKIP: this host cannot run x86_64 programs'; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/udp-wait.XXXXXX")"
trap 'rm -rf "$work"' EXIT
/usr/bin/clang $FLAGS -arch x86_64 -Wall -Wextra -Werror \
  -isystem "$T/include/recaulk" tests/c/udp_wait.c "$T/lib/librecaulk.a" \
  -o "$work/test"
"$work/test"
