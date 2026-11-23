#!/bin/sh
# platform: host-agnostic
: "${MAVERICKS_ROOT:=$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." 2>/dev/null && pwd || pwd)}"
export MAVERICKS_ROOT
. "$MAVERICKS_ROOT/build/msc.sh"
. "$SHIPYARD/lib.sh"

macports_pin() {
  _mp_value="$(sed -n "s/^$1=//p" "$MAVERICKS_ROOT/components/macports-legacy-support/version")"
  [ -n "$_mp_value" ] || { echo "macports_pin: no $1 in components/macports-legacy-support/version" >&2; exit 1; }
  printf '%s\n' "$_mp_value"
}

macports_version() {
  _mp_ref="$(macports_pin REF)" || exit 1
  printf '%s\n' "${_mp_ref#v}"
}

recaulk_build_dir() {
  printf '%s\n' "${RECAULK_BUILD:-${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/$(basename "$MAVERICKS_ROOT")}"
}

recaulk_tools() {
  CL="${CL:-$(sh "$MAVERICKS_ROOT/build/fetch-clang22.sh")}" || return 1
  CC="$CL/bin/clang"; CXX="$CL/bin/clang++"; AR="$CL/bin/llvm-ar"
  NM="${NM:-$CL/bin/llvm-nm}"; OTOOL="${OTOOL:-$CL/bin/llvm-otool}"
  LIPO="${LIPO:-$CL/bin/llvm-lipo}"; STRINGS="${STRINGS:-$CL/bin/llvm-strings}"
  TARGET_FLAGS="--no-default-config --target=x86_64-apple-macos10.9 -mmacosx-version-min=10.9"
  export CL NM OTOOL LIPO STRINGS
}

# platform: the SDK path may hold a space, so it goes to clang as one argument, never through a flags string
recaulk_cc() {
  "$CC" $TARGET_FLAGS -isysroot "$SDK" "$@"
}

# platform: make hands CC, CFLAGS and the like to sh, which splits them into words, so a path in one (the
#           checkout's or the build tree's, which may hold a space) goes in as one shell word: this prints
#           its argument single-quoted for sh
recaulk_shq() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

recaulk_archive() {
  _ra_out="$1"; shift
  rm -f "$_ra_out"
  "$AR" --format=darwin rcs "$_ra_out" "$@"
}
