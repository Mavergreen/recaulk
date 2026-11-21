#!/bin/sh
# platform: host-agnostic -- links an x86_64 dylib from the staged archive; reads exports with nm
# spec: README.md "Fixes to functions 10.9 has" -- a chdir action builder works only with the posix_spawn that
#       carries it out, so a dylib built from librecaulk.a exports both or neither. rust's stage0 dylib (the archive
#       force-loaded) exported posix_spawn_file_actions_addchdir_np but not the hidden posix_spawnp: std found the
#       builder by dlsym, spawned with libSystem's posix_spawnp, and the child ran in the parent's directory.
#       libRecaulkSystem.dylib exports all of them.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
d="$(mktemp -d "${TMPDIR:-/tmp}/spawn-pairs.XXXXXX")"
trap 'rm -rf "$d"' EXIT
builders='_posix_spawn_file_actions_addchdir_np _posix_spawn_file_actions_addfchdir_np'
spawns='_posix_spawn _posix_spawnp'
printf 'int lib_marker(void) { return 0; }\n' > "$d/lib.c"
"$CC" $FLAGS -arch x86_64 -dynamiclib "$d/lib.c" -Wl,-force_load,"$T/lib/librecaulk.a" -o "$d/archive.dylib"
exports() { "$NM" -gU "$1" | awk 'NF >= 3 { print $NF }' | LC_ALL=C sort -u; }
exports "$d/archive.dylib" > "$d/archive"
exports "$T/lib/libRecaulkSystem.dylib" > "$d/system"
grep -qx _lib_marker "$d/archive" || bad "control: the dylib does not export its own lib_marker, so this test reads nothing"
n=0
for s in $builders $spawns; do grep -qxF -- "$s" "$d/archive" && n=$((n + 1)); done
[ "$n" = 0 ] || [ "$n" = 4 ] || bad "a dylib force-loading librecaulk.a exports $n of $builders $spawns: a half pair ($(for s in $builders $spawns; do grep -qxF -- "$s" "$d/archive" && printf '%s ' "$s"; done))"
for s in $builders $spawns; do
  grep -qxF -- "$s" "$d/system" || bad "libRecaulkSystem.dylib does not export $s"
done
[ "$fail" = 0 ] && echo "spawn-chdir-pairs OK"
exit $fail
