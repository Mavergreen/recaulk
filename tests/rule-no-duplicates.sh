#!/bin/sh
# platform: macOS-only -- nm reads Mach-O archives
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
. build/duplicates.sh

tmp="$(mktemp -d "${TMPDIR:-/tmp}/rule2.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail=0

mkdir "$tmp/fx"
printf 'int probe(void) { return 0; }\n' > "$tmp/fx/fwd-probe.c"
# platform: an __asm__ label names the Mach-O symbol directly, so this object defines ___recaulk_impl_probe
printf 'int impl_probe(void) __asm__("___recaulk_impl_probe");\nint impl_probe(void) { return 1; }\n' > "$tmp/fx/mp-probe.c"
cp "$tmp/fx/mp-probe.c" "$tmp/fx/recaulk-probe.c"
cp "$tmp/fx/mp-probe.c" "$tmp/fx/recaulk-probe2.c"
for n in fwd-probe mp-probe recaulk-probe recaulk-probe2; do
  /usr/bin/clang $FLAGS -arch x86_64 -c "$tmp/fx/$n.c" -o "$tmp/fx/$n.o"
done
/usr/bin/libtool -static -o "$tmp/fx/ok.a" "$tmp/fx/fwd-probe.o" "$tmp/fx/mp-probe.o" 2>/dev/null
/usr/bin/libtool -static -o "$tmp/fx/macports.a" "$tmp/fx/mp-probe.o" "$tmp/fx/recaulk-probe.o" 2>/dev/null
/usr/bin/libtool -static -o "$tmp/fx/ours.a" "$tmp/fx/recaulk-probe.o" "$tmp/fx/recaulk-probe2.o" 2>/dev/null
out="$(duplicate_report "$tmp/fx/ok.a")"
[ -z "$out" ] || { echo "FAIL: self-test: a trampoline _probe beside ___recaulk_impl_probe read as a duplicate: $out"; fail=1; }
out="$(duplicate_report "$tmp/fx/macports.a")"
case "$out" in
  *"FAIL: _probe is defined by more than one member: mp-probe.o recaulk-probe.o -- MacPorts now carries _probe: delete ours"*) ;;
  *) echo "FAIL: self-test: a MacPorts member and ours both defining ___recaulk_impl_probe was not reported as MacPorts now carrying _probe: $out"; fail=1 ;;
esac
out="$(duplicate_report "$tmp/fx/ours.a")"
case "$out" in
  *"FAIL: _probe is defined by more than one member: recaulk-probe.o recaulk-probe2.o -- every one of them is ours: delete our own duplicate"*) ;;
  *) echo "FAIL: self-test: two of our members defining ___recaulk_impl_probe were not reported as our own duplicate: $out"; fail=1 ;;
esac
[ "$fail" = 0 ] || exit 1

report="$(duplicate_report "$T/lib/librecaulk.a" "$W/librecaulk-overrides.a")"
if [ -n "$report" ]; then
  printf '%s\n' "$report"
  exit 1
fi
echo "rule 2 OK"
