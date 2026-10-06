#!/bin/sh
# platform: macOS-only -- links and runs an x86_64 program against librecaulk.a
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
x86_64_runs || { echo "SKIP: this host cannot run x86_64 programs"; exit 77; }
D="$(mktemp -d "${TMPDIR:-/tmp}/ksec-values.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

want=tests/fixtures/ksec-values.txt
cut -f1 "$want" | LC_ALL=C sort > "$D/names"
nm -gU "$T/lib/librecaulk.a" | awk 'NF == 3 && $2 != "T" && $3 ~ /^_kSec/ { print substr($3, 2) }' | LC_ALL=C sort -u > "$D/defined"
if ! diff "$D/names" "$D/defined" > "$D/names.diff"; then
  bad "$want must pin every kSec constant librecaulk.a defines (< pinned but not defined, > defined but not pinned):"
  sed -n 's/^\([<>]\)/  \1/p' "$D/names.diff"
fi

{
  echo '#include <CoreFoundation/CoreFoundation.h>'
  echo '#include <stdio.h>'
  while read -r n; do echo "extern const CFStringRef $n;"; done < "$D/names"
  echo 'static void show(const char *name, CFStringRef s) {'
  echo '  char buf[256];'
  echo '  if (!CFStringGetCString(s, buf, sizeof(buf), kCFStringEncodingUTF8)) buf[0] = 0;'
  printf '%s\n' '  printf("%s\t%s\n", name, buf);'
  echo '}'
  echo 'int main(void) {'
  while read -r n; do echo "  show(\"$n\", $n);"; done < "$D/names"
  echo '  return 0;'
  echo '}'
} > "$D/ksec.c"
/usr/bin/clang $FLAGS -arch x86_64 -o "$D/ksec" "$D/ksec.c" "$T/lib/librecaulk.a" -framework CoreFoundation \
  || { echo "FAIL: a program reading the kSec constants does not link with librecaulk.a"; exit 1; }
"$D/ksec" > "$D/got" || { echo "FAIL: the kSec program exited non-zero"; exit 1; }
LC_ALL=C sort "$want" > "$D/want"
if ! diff "$D/want" "$D/got" > "$D/values.diff"; then
  bad "a kSec constant's string is not Apple's (spec, back-fills match the real API; values and sources in PROVENANCE.md), < Apple's, > ours:"
  sed -n 's/^\([<>]\)/  \1/p' "$D/values.diff"
fi

[ "$fail" = 0 ] && echo "ksec-values OK ($(wc -l < "$D/want" | tr -d ' ') constants)"
exit $fail
