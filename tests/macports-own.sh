#!/bin/sh
# platform: macOS-only -- executes x86_64 Mach-O
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. tests/helpers/macports-own.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
D="$(mktemp -d "${TMPDIR:-/tmp}/macports-own.XXXXXX")"
trap 'rm -rf "$D"' EXIT
# platform: the make on PATH may be a wrapper; MacPorts' Makefile needs GNU make.
/usr/bin/make -k -C "$W/macports-legacy-support-$(macports_version)" CC=/usr/bin/clang ARCHS=x86_64 \
  CFLAGS="$FLAGS" LDFLAGS="$FLAGS" test_static > "$D/make.log" 2>&1 && rc=0 || rc=$?
cat "$D/make.log"
# platform: hw.optional.arm64 is 1 on Apple silicon, where every x86_64 program runs under Rosetta 2; 10.9 has no such sysctl
rosetta=0
[ "$(sysctl -n hw.optional.arm64 2>/dev/null || :)" != 1 ] || rosetta=1
macports_own_verdict "$D/make.log" "$rc" "$rosetta" tests/fixtures/macports-own-rosetta.txt || exit 1
echo "macports-own OK"
