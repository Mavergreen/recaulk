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
# platform: flags is shell words, for make and apsl-notices.sh, which hand it to sh; the SDK path in it is
#           single-quoted, since it may hold a space
flags="$TARGET_FLAGS -isysroot $(recaulk_shq "$SDK")"
if [ "$(uname -s)" = Darwin ]; then MAKE=/usr/bin/make; else MAKE=make; fi

rm -rf "$B/stage"
mkdir -p "$T/lib" "$T/include/recaulk" "$W"
sh "$SELF/stage-sdk-metadata.sh" "$MAVERICKS_ROOT/sdk-metadata" "$T/share/sdk-metadata"
src="$(sh "$SELF/fetch-macports.sh" "$W")"

mp_slib() {
  # platform: MacPorts' Makefile compiles and runs a probe program to choose TESTARCHS unless it is given
  "$MAKE" -C "$src" "$@" CC="$(recaulk_shq "$CC")" ARCHS=x86_64 TESTARCHS=x86_64 CFLAGS="$flags" LDFLAGS="$flags" \
    ARX="$(recaulk_shq "$AR")" BUILDSLIBFLAGS="--format=darwin -qs" slib 1>&2
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

rm -rf "$W/mp-headers" "$src/_recaulk_mp_headers"
# platform: MacPorts' Makefile names make targets after DESTDIR, which no quoting keeps whole, so the headers
#           go to a directory relative to $src, free of the space its absolute path may hold, and then to $W
"$MAKE" -C "$src" PREFIX=/ DESTDIR=_recaulk_mp_headers TESTARCHS=x86_64 install-headers 1>&2
mv "$src/_recaulk_mp_headers" "$W/mp-headers"
# spec: README.md requires the pinned MacPorts source to remain unmodified.
# platform: MacPorts headers adapt declarations to the target SDK; wrappers must follow them.
mp="$W/mp-headers/include/LegacySupport"
cp -R "$mp/." "$T/include/recaulk/"
rm -rf "$W/own-include"
cp -R "$MAVERICKS_ROOT/src/include" "$W/own-include"
for h in $(cd "$MAVERICKS_ROOT/src/include" && find . -type f | sed 's|^\./||'); do
  [ -f "$mp/$h" ] || continue
  mv "$T/include/recaulk/$h" "$T/include/recaulk/$(dirname "$h")/_recaulk_macports_$(basename "$h")"
  rm "$W/own-include/$h"
done
cp -R "$MAVERICKS_ROOT/src/include/." "$T/include/recaulk/"

NM="$NM" sh "$SELF/member-link-options.sh" map "$SDK" > "$W/link-options.map"
mkdir -p "$W/link-options"
for dir in backfills overrides; do
  mkdir -p "$W/$dir"
  rm -f "$W/$dir"/*.o "$W/librecaulk-$dir.a"
  for c in "$MAVERICKS_ROOT/src/$dir"/*.c; do
    o="$W/$dir/recaulk-$(basename "$c" .c).o"
    set -- -arch x86_64 -Os -fPIC -Wall -Wno-deprecated-declarations -D__RECAULK_SOURCE__ \
      -I"$W/own-include" -I"$MAVERICKS_ROOT/src" -I"$src/include" -c "$c" -o "$o"
    recaulk_cc "$@"
    # spec: README.md "How to use" -- a member carries the frameworks and libraries it needs; measured from the
    #       compiled object, then compiled again with them
    [ "$dir" = backfills ] || continue
    h="$W/link-options/$(basename "$c" .c).h"
    NM="$NM" sh "$SELF/member-link-options.sh" header "$W/link-options.map" "$o" > "$h"
    [ -s "$h" ] && recaulk_cc "$@" -include "$h"
  done
  recaulk_archive "$W/librecaulk-$dir.a" "$W/$dir"/recaulk-*.o
done
# spec: README.md "C++ exceptions" -- the pointer catch vtables, public, for libcxx22's
#       libc++abi.1.dylib to export; librecaulk.a keeps them hidden.
mkdir -p "$W/cxxabi-exports" "$T/lib"
recaulk_cc -arch x86_64 -Os -fPIC -Wall -DRECAULK_CXXABI_EXPORTS \
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
# spec: build/macports-superseded.txt -- members of Recaulk's own replace these; a name not in the archive is an error
for m in $(grep -v '^#' "$SELF/macports-superseded.txt" | awk 'NF { print $1 }'); do
  [ -f "$F/mp/$m" ] || { echo "build-lib: build/macports-superseded.txt names $m, which MacPorts' archive lacks" >&2; exit 1; }
  rm -f "$F/mp/$m"
done
for m in "$F/mp"/*.o; do
  mv "$m" "$F/mp/mp-$(basename "$m")"
done
cp "$W/backfills"/recaulk-*.o "$F/bf/"
sh "$SELF/rename-impls.sh" "$DRYDOCK" "$F/symbols.txt" "$F/mp"/mp-*.o "$F/bf"/recaulk-*.o
SDK="$SDK" sh "$SELF/gen-trampolines.sh" "$F/symbols.txt" "$F"
# spec: tests/parity.sh -- libRecaulkSystem.dylib keeps exporting MacPorts' private names, as libSystemWrapper.dylib does
recaulk_archive "$W/librecaulk-dylib.a" "$F/mp"/mp-*.o "$F/bf"/recaulk-*.o "$F"/fwd-*.o
sh "$SELF/rename-private.sh" "$DRYDOCK" "$F/mp"/mp-*.o "$F/bf"/recaulk-*.o
# spec: build/image-local-backfills.txt -- in librecaulk.a those back-fills' trampolines are hidden, as the fixes they
#       need are; gen-trampolines.sh numbered fwd-<i> by the non-empty lines of symbols.txt
grep -v '^#' "$SELF/image-local-backfills.txt" | awk 'NF { print $1 }' > "$W/image-local-backfills"
rm -rf "$F/static"
mkdir -p "$F/static"
cp "$F/fwd-resolve.o" "$F/static/"
i=0
while IFS= read -r sym; do
  [ -n "$sym" ] || continue
  i=$((i + 1))
  if grep -qxF -- "$sym" "$W/image-local-backfills"; then
    awk -v s="$sym" '{ print } $1 == ".globl" && $2 == "\"" s "\"" { print "\t.private_extern\t\"" s "\"" }' \
      "$F/fwd-$i.s" > "$F/static/fwd-$i.s"
    grep -q '\.private_extern.*"'"$sym"'"$' "$F/static/fwd-$i.s" \
      || { echo "build-lib: fwd-$i.s does not define $sym as gen-trampolines.sh writes it" >&2; exit 1; }
    recaulk_cc -arch x86_64 -c "$F/static/fwd-$i.s" -o "$F/static/fwd-$i.o"
  else
    cp "$F/fwd-$i.o" "$F/static/"
  fi
done < "$F/symbols.txt"
while IFS= read -r sym; do
  grep -qxF -- "$sym" "$F/symbols.txt" \
    || { echo "build-lib: build/image-local-backfills.txt lists $sym, which the forwarding layer does not carry" >&2; exit 1; }
done < "$W/image-local-backfills"
recaulk_archive "$T/lib/librecaulk.a" "$F/mp"/mp-*.o "$F/bf"/recaulk-*.o "$F/static"/fwd-*.o

. "$SELF/duplicates.sh"
dups="$(duplicate_report "$W/librecaulk-dylib.a" "$W/librecaulk-overrides.a")"
[ -z "$dups" ] || {
  printf '%s\n' "$dups" >&2
  echo "build-lib: rule 2 (README): a symbol is defined twice, so libRecaulkSystem.dylib would not link" >&2
  exit 1
}

# spec: build/header-entries.txt -- the dylib keeps Recaulk's ___recaulk_ names private but these, which a program
#       built against Recaulk's headers references
grep -v '^#' "$MAVERICKS_ROOT/build/header-entries.txt" | awk 'NF' | LC_ALL=C sort > "$W/header-entries"
"$NM" -gU "$W/librecaulk-dylib.a" "$W/librecaulk-overrides.a" | awk '{ print $NF }' | grep '^___recaulk_' \
  | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$W/header-entries" > "$W/unexported"
recaulk_cc -dynamiclib -arch x86_64 -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -o "$T/lib/libRecaulkSystem.dylib" \
  -Wl,-reexport_library,/usr/lib/libSystem.B.dylib \
  -Wl,-force_load,"$W/librecaulk-dylib.a" -Wl,-force_load,"$W/librecaulk-overrides.a" \
  -Wl,-unexported_symbols_list,"$W/unexported" \
  -install_name /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib \
  -compatibility_version 1.0.0 -current_version 1356.0.0 \
  -framework CoreFoundation -framework Security -framework CoreVideo \
  -framework CoreGraphics -framework CoreServices -lobjc -lc++abi

mkdir -p "$T/share/recaulk"
# spec: README.md "How to use" -- every global librecaulk.a defines, for a dylib's -Wl,-unexported_symbols_list
"$NM" -gU "$T/lib/librecaulk.a" | awk 'NF >= 3 { print $NF }' | LC_ALL=C sort -u > "$T/share/recaulk/unexported-symbols.txt"
# spec: README.md "How to use" -- the system exports a member shadows inside its image, for a consumer that
#       links a subset of the archive
cp "$SELF/image-local-shadows.txt" "$T/share/recaulk/image-local-shadows.txt"
# spec: README.md "Fixes to functions 10.9 has" -- every global librecaulk.a defines that 10.9 already exports, for a
#       product's check that no binary imports one from the system instead
. "$SELF/sdk-exports.sh"
sdk_exports "$SDK" > "$W/sdk-exports.txt"
{
  echo '# <member> <symbol>: librecaulk.a defines <symbol>, which 10.9 already exports'
  # platform: nm -A prefixes each line with the archive path as given, which may hold a space; from its own
  #           directory that prefix is librecaulk.a, so $1 is the archive and member
  (cd "$T/lib" && "$NM" -gU -m -A librecaulk.a) \
    | awk '$NF !~ /\.eh$/ { m = $1; sub(/^.*\.a:/, "", m); sub(/:$/, "", m); print m, $NF }' \
    | while read -r m s; do grep -qxF -- "$s" "$W/sdk-exports.txt" && echo "$m $s"; done | LC_ALL=C sort -u
} > "$T/share/recaulk/system-overrides.txt"
{
  printf '# artifact\tmember\tlicence\tcovered-files\tcopyright\tsource-urls\tnotice\n'
  for a in librecaulk.a libRecaulkSystem.dylib; do
    sed "s/^/$a$(printf '\t')/" "$W/apsl/rows.tsv"
  done
} > "$T/share/recaulk/notices.tsv"

printf "build-make=%s\n" "$("$MAKE" --version | sed -n 1p)" > "$B/build-tools.txt"

SDK="$SDK" sh "$SELF/build-objc.sh" "$T" "$W/objc-companion" 1>&2

printf '%s\n' "$B"
