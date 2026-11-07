#!/bin/sh
# platform: host-agnostic -- links an x86_64 program against librecaulk.a; runs it on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
D="$(mktemp -d "${TMPDIR:-/tmp}/ksec-values.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

want=tests/fixtures/ksec-values.txt
if compiling; then
  cut -f1 "$want" | LC_ALL=C sort > "$D/names"
  "$NM" -gU "$T/lib/librecaulk.a" | awk 'NF == 3 && $2 != "T" && $3 ~ /^_kSec/ { print substr($3, 2) }' | LC_ALL=C sort -u > "$D/defined"
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
  "$CC" $FLAGS -arch x86_64 -o "$(tbin ksec)" "$D/ksec.c" "$T/lib/librecaulk.a" -framework CoreFoundation \
    || { echo "FAIL: a program reading the kSec constants does not link with librecaulk.a"; exit 1; }
  check_loads "$(tbin ksec)"
  [ "$fail" = 0 ] || exit 1
fi
runtime_half
"$(tbin ksec)" > "$D/got" || { echo "FAIL: the kSec program exited non-zero"; exit 1; }
LC_ALL=C sort "$want" > "$D/want"
if ! diff "$D/want" "$D/got" > "$D/values.diff"; then
  bad "a kSec constant's string is not Apple's (spec, back-fills match the real API; values and sources in PROVENANCE.md), < Apple's, > ours:"
  sed -n 's/^\([<>]\)/  \1/p' "$D/values.diff"
fi

[ "$fail" = 0 ] && echo "ksec-values OK ($(wc -l < "$D/want" | tr -d ' ') constants)"
exit $fail
