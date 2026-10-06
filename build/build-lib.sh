#!/bin/sh
# platform: macOS-only -- links Mach-O archives and a dylib with Apple's libtool and clang
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"

B="$(recaulk_build_dir)"
T="$B/stage/usr/local/mavergreen/recaulk"
W="$B/work"
if [ -z "${SDK:-}" ]; then
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
fi
flags="-isysroot $SDK -mmacosx-version-min=10.9"
MAKE=/usr/bin/make

rm -rf "$B/stage"
mkdir -p "$T/lib" "$T/include/recaulk" "$W"
src="$(sh "$SELF/fetch-macports.sh" "$W")"

# platform: /usr/bin/clang and /usr/bin/libtool by absolute path -- pkgsrc's GNU libtool shadows Apple's on PATH
"$MAKE" -C "$src" CC=/usr/bin/clang ARCHS=x86_64 CFLAGS="$flags" LDFLAGS="$flags" slib 1>&2

rm -rf "$W/mp-headers"
"$MAKE" -C "$src" PREFIX=/ DESTDIR="$W/mp-headers" install-headers 1>&2
cp -R "$W/mp-headers/include/LegacySupport/." "$T/include/recaulk/"

for dir in backfills overrides; do
  mkdir -p "$W/$dir"
  rm -f "$W/$dir"/*.o "$W/librecaulk-$dir.a"
  for c in "$MAVERICKS_ROOT/src/$dir"/*.c; do
    /usr/bin/clang $flags -arch x86_64 -Os -fPIC -Wall -Wno-deprecated-declarations \
      -I"$MAVERICKS_ROOT/src/include" -I"$MAVERICKS_ROOT/src" -I"$src/include" \
      -c "$c" -o "$W/$dir/recaulk-$(basename "$c" .c).o"
  done
  /usr/bin/libtool -static -o "$W/librecaulk-$dir.a" "$W/$dir"/recaulk-*.o
done
cp -R "$MAVERICKS_ROOT/src/include/." "$T/include/recaulk/"

mkdir -p "$B/drydock"
DRYDOCK="$(sh "$SELF/fetch-drydock.sh" "$(cat "$MAVERICKS_ROOT/components/drydock/version")" "$B/drydock")"
F="$W/forward"
rm -rf "$F"
mkdir -p "$F/mp" "$F/bf"
sh "$SELF/forward-set.sh" "$SDK" "$src/lib/libMacportsLegacySupport.a" "$W/librecaulk-backfills.a" > "$F/symbols.txt"
dups="$(/usr/bin/ar -t "$src/lib/libMacportsLegacySupport.a" | LC_ALL=C sort | uniq -d | tr '\n' ' ')"
[ -z "$dups" ] || { echo "build-lib: libMacportsLegacySupport.a has members sharing a name, which ar -x would overwrite: $dups" >&2; exit 1; }
(cd "$F/mp" && /usr/bin/ar -x "$src/lib/libMacportsLegacySupport.a")
rm -f "$F/mp"/__.SYMDEF*
for m in "$F/mp"/*.o; do
  mv "$m" "$F/mp/mp-$(basename "$m")"
done
cp "$W/backfills"/recaulk-*.o "$F/bf/"
sh "$SELF/rename-impls.sh" "$DRYDOCK" "$F/symbols.txt" "$F/mp"/mp-*.o "$F/bf"/recaulk-*.o
SDK="$SDK" sh "$SELF/gen-trampolines.sh" "$F/symbols.txt" "$F"
/usr/bin/libtool -static -o "$T/lib/librecaulk.a" "$F/mp"/mp-*.o "$F/bf"/recaulk-*.o "$F"/fwd-*.o

. "$SELF/duplicates.sh"
dups="$(duplicate_report "$T/lib/librecaulk.a" "$W/librecaulk-overrides.a")"
[ -z "$dups" ] || {
  printf '%s\n' "$dups" >&2
  echo "build-lib: rule 2 (README): a symbol is defined twice, so libRecaulkSystem.dylib would not link" >&2
  exit 1
}

/usr/bin/clang -dynamiclib $flags -arch x86_64 -o "$T/lib/libRecaulkSystem.dylib" \
  -Wl,-reexport_library,/usr/lib/libSystem.B.dylib \
  -Wl,-force_load,"$T/lib/librecaulk.a" -Wl,-force_load,"$W/librecaulk-overrides.a" \
  '-Wl,-unexported_symbol,___recaulk_*' \
  -install_name /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib \
  -compatibility_version 1.0.0 -current_version 1356.0.0 \
  -framework CoreFoundation -framework Security -framework CoreVideo \
  -framework CoreGraphics -framework CoreServices -lobjc

printf '%s\n' "$B"
