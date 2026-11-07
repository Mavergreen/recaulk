#!/bin/sh
# platform: host-agnostic -- nm reads Mach-O archives
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
  "$CC" $FLAGS -arch x86_64 -c "$tmp/fx/$n.c" -o "$tmp/fx/$n.o"
done
recaulk_archive "$tmp/fx/ok.a" "$tmp/fx/fwd-probe.o" "$tmp/fx/mp-probe.o" 2>/dev/null
recaulk_archive "$tmp/fx/macports.a" "$tmp/fx/mp-probe.o" "$tmp/fx/recaulk-probe.o" 2>/dev/null
recaulk_archive "$tmp/fx/ours.a" "$tmp/fx/recaulk-probe.o" "$tmp/fx/recaulk-probe2.o" 2>/dev/null
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
printf '__attribute__((weak, visibility("hidden"))) int shadow(void) { return 0; }\n' > "$tmp/fx/recaulk-weak.c"
printf 'int shadow(void) { return 1; }\n' > "$tmp/fx/recaulk-public.c"
printf '__attribute__((visibility("hidden"))) int shadow(void) { return 0; }\n' > "$tmp/fx/recaulk-hidden.c"
for n in recaulk-weak recaulk-public recaulk-hidden; do
  "$CC" $FLAGS -arch x86_64 -c "$tmp/fx/$n.c" -o "$tmp/fx/$n.o"
done
recaulk_archive "$tmp/fx/weak.a" "$tmp/fx/recaulk-weak.o" 2>/dev/null
recaulk_archive "$tmp/fx/public.a" "$tmp/fx/recaulk-public.o" 2>/dev/null
recaulk_archive "$tmp/fx/hidden.a" "$tmp/fx/recaulk-hidden.o" 2>/dev/null
out="$(duplicate_report "$tmp/fx/weak.a" "$tmp/fx/public.a")"
[ -z "$out" ] || { echo "FAIL: self-test: a weak hidden _shadow beside a public one read as a duplicate, though the public one always wins the link: $out"; fail=1; }
out="$(duplicate_report "$tmp/fx/hidden.a" "$tmp/fx/public.a")"
case "$out" in
  *"FAIL: _shadow is defined by more than one member: recaulk-hidden.o recaulk-public.o"*) ;;
  *) echo "FAIL: self-test: a hidden but strong _shadow beside a public one was not reported, though the two collide in libRecaulkSystem.dylib's link: $out"; fail=1 ;;
esac
[ "$fail" = 0 ] || exit 1

report="$(duplicate_report "$T/lib/librecaulk.a" "$W/librecaulk-overrides.a")"
if [ -n "$report" ]; then
  printf '%s\n' "$report"
  exit 1
fi
echo "rule 2 OK"
