#!/bin/sh
# platform: host-agnostic
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"

B="$(recaulk_build_dir)"
T="$B/stage/usr/local/mavergreen/recaulk"
W="$B/work"
if [ -z "${SDK:-}" ]; then
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
fi
recaulk_tools
flags="$TARGET_FLAGS -isysroot $SDK"
if [ "$(uname -s)" = Darwin ]; then MAKE=/usr/bin/make; else MAKE=make; fi

rm -rf "$B/stage"
mkdir -p "$T/lib" "$T/include/recaulk" "$W"
src="$(sh "$SELF/fetch-macports.sh" "$W")"

mp_slib() {
  # platform: MacPorts' Makefile compiles and runs a probe program to choose TESTARCHS unless it is given
  "$MAKE" -C "$src" "$@" CC="$CC" ARCHS=x86_64 TESTARCHS=x86_64 CFLAGS="$flags" LDFLAGS="$flags" \
    ARX="$AR" BUILDSLIBFLAGS="--format=darwin -qs" slib 1>&2
}
mp_slib
# spec: README.md "Licences" -- the second pass recompiles only the Apple-derived members MacPorts kept
apsl="$(AR="$AR" CC="$CC" MP_CFLAGS="$flags" sh "$SELF/apsl-notices.sh" "$src" "$W/apsl")"
for stem in $apsl; do rm -f "$src/bin/$stem.o"; done
mp_slib -f Makefile -f "$W/apsl/notices.mk"
for stem in $apsl; do
  "$NM" "$src/bin/$stem.o" | grep -q ' s _recaulk_apsl_notice$' \
    || { echo "build-lib: MacPorts' $stem.o was rebuilt without its APSL notice; did its Makefile's object path change?" >&2; exit 1; }
done

rm -rf "$W/mp-headers"
"$MAKE" -C "$src" PREFIX=/ DESTDIR="$W/mp-headers" TESTARCHS=x86_64 install-headers 1>&2
# spec: README.md requires the pinned MacPorts source to remain unmodified.
# platform: MacPorts headers adapt declarations to the target SDK; wrappers must follow them.
mp="$W/mp-headers/include/LegacySupport"
cp -R "$mp/." "$T/include/recaulk/"
rm -rf "$W/own-include"
cp -R "$MAVERICKS_ROOT/src/include" "$W/own-include"
for h in $(cd "$MAVERICKS_ROOT/src/include" && find . -type f | sed 's|^\./||'); do
  [ -f "$mp/$h" ] || continue
  mkdir -p "$T/include/recaulk/_recaulk_macports/$(dirname "$h")"
  mv "$T/include/recaulk/$h" "$T/include/recaulk/_recaulk_macports/$h"
  rm "$W/own-include/$h"
done
cp -R "$MAVERICKS_ROOT/src/include/." "$T/include/recaulk/"

for dir in backfills overrides; do
  mkdir -p "$W/$dir"
  rm -f "$W/$dir"/*.o "$W/librecaulk-$dir.a"
  for c in "$MAVERICKS_ROOT/src/$dir"/*.c; do
    "$CC" $flags -arch x86_64 -Os -fPIC -Wall -Wno-deprecated-declarations \
      -I"$W/own-include" -I"$MAVERICKS_ROOT/src" -I"$src/include" \
      -c "$c" -o "$W/$dir/recaulk-$(basename "$c" .c).o"
  done
  recaulk_archive "$W/librecaulk-$dir.a" "$W/$dir"/recaulk-*.o
done
# spec: README.md "C++ exceptions" -- the pointer catch vtables, public, for libcxx22's
#       libc++abi.1.dylib to export; librecaulk.a keeps them hidden.
mkdir -p "$W/cxxabi-exports" "$T/lib"
"$CC" $flags -arch x86_64 -Os -fPIC -Wall -DRECAULK_CXXABI_EXPORTS \
  -c "$MAVERICKS_ROOT/src/backfills/cxxabi_pointer_catch.c" -o "$W/cxxabi-exports/recaulk-cxxabi_pointer_catch.o"
recaulk_archive "$T/lib/librecaulk-cxxabi-exports.a" "$W/cxxabi-exports/recaulk-cxxabi_pointer_catch.o"

mkdir -p "$B/drydock"
DRYDOCK="$(sh "$SELF/fetch-drydock.sh" "$(cat "$MAVERICKS_ROOT/components/drydock/version")" "$B/drydock")"
F="$W/forward"
rm -rf "$F"
mkdir -p "$F/mp" "$F/bf"
sh "$SELF/forward-set.sh" "$SDK" "$src/lib/libMacportsLegacySupport.a" "$W/librecaulk-backfills.a" > "$F/symbols.txt"
dups="$("$AR" -t "$src/lib/libMacportsLegacySupport.a" | grep -v '^__\.SYMDEF' | LC_ALL=C sort | uniq -d | tr '\n' ' ')"
[ -z "$dups" ] || { echo "build-lib: libMacportsLegacySupport.a has members sharing a name, which ar -x would overwrite: $dups" >&2; exit 1; }
(cd "$F/mp" && "$AR" -x "$src/lib/libMacportsLegacySupport.a")
rm -f "$F/mp"/__.SYMDEF*
for m in "$F/mp"/*.o; do
  mv "$m" "$F/mp/mp-$(basename "$m")"
done
cp "$W/backfills"/recaulk-*.o "$F/bf/"
sh "$SELF/rename-impls.sh" "$DRYDOCK" "$F/symbols.txt" "$F/mp"/mp-*.o "$F/bf"/recaulk-*.o
SDK="$SDK" sh "$SELF/gen-trampolines.sh" "$F/symbols.txt" "$F"
recaulk_archive "$T/lib/librecaulk.a" "$F/mp"/mp-*.o "$F/bf"/recaulk-*.o "$F"/fwd-*.o

. "$SELF/duplicates.sh"
dups="$(duplicate_report "$T/lib/librecaulk.a" "$W/librecaulk-overrides.a")"
[ -z "$dups" ] || {
  printf '%s\n' "$dups" >&2
  echo "build-lib: rule 2 (README): a symbol is defined twice, so libRecaulkSystem.dylib would not link" >&2
  exit 1
}

"$CC" -dynamiclib $flags -arch x86_64 -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -o "$T/lib/libRecaulkSystem.dylib" \
  -Wl,-reexport_library,/usr/lib/libSystem.B.dylib \
  -Wl,-force_load,"$T/lib/librecaulk.a" -Wl,-force_load,"$W/librecaulk-overrides.a" \
  '-Wl,-unexported_symbol,___recaulk_*' \
  -install_name /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib \
  -compatibility_version 1.0.0 -current_version 1356.0.0 \
  -framework CoreFoundation -framework Security -framework CoreVideo \
  -framework CoreGraphics -framework CoreServices -lobjc -lc++abi

mkdir -p "$T/share/recaulk"
{
  printf '# artifact\tmember\tlicence\tcovered-files\tcopyright\tsource-urls\tnotice\n'
  for a in librecaulk.a libRecaulkSystem.dylib; do
    sed "s/^/$a$(printf '\t')/" "$W/apsl/rows.tsv"
  done
} > "$T/share/recaulk/notices.tsv"

printf "build-make=%s\n" "$("$MAKE" --version | sed -n 1p)" > "$B/build-tools.txt"

printf '%s\n' "$B"
