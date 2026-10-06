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

/usr/bin/libtool -static -o "$T/lib/librecaulk.a" "$src/lib/libMacportsLegacySupport.a"

/usr/bin/clang -dynamiclib $flags -arch x86_64 -o "$T/lib/libRecaulkSystem.dylib" \
  -Wl,-reexport_library,/usr/lib/libSystem.B.dylib -Wl,-force_load,"$T/lib/librecaulk.a" \
  -install_name /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib \
  -compatibility_version 1.0.0 -current_version 1356.0.0 \
  -framework CoreFoundation -framework Security -framework CoreVideo \
  -framework CoreGraphics -framework CoreServices -lobjc

printf '%s\n' "$B"
