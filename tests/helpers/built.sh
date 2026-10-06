#!/bin/sh
# platform: macOS-only -- reads what build-lib.sh built and compiles x86_64 Mach-O
. build/lib.sh
B="$(recaulk_build_dir)"
T="$B/stage/usr/local/mavergreen/recaulk"
W="$B/work"
[ -f "$T/lib/librecaulk.a" ] || { echo "not built: run sh build/build-lib.sh first"; exit 77; }
if [ -z "${SDK:-}" ]; then
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
fi
FLAGS="-isysroot $SDK -mmacosx-version-min=10.9"

x86_64_runs() {
  _x_dir="$(mktemp -d "${TMPDIR:-/tmp}/x86run.XXXXXX")"
  printf 'int main(void) { return 0; }\n' > "$_x_dir/t.c"
  if /usr/bin/clang $FLAGS -arch x86_64 -o "$_x_dir/t" "$_x_dir/t.c" 2>/dev/null && "$_x_dir/t" 2>/dev/null; then
    _x_rc=0
  else
    _x_rc=1
  fi
  rm -rf "$_x_dir"
  return $_x_rc
}
