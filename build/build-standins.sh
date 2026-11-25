#!/bin/sh
# platform: host-agnostic
#   usage: build-standins.sh STAGE_PREFIX WORK_DIR
#          builds libRecaulkAppKit.dylib (lib/stand-in/) from build/standins.txt, each class exported under the AppKit
#          name it stands in for, and its stub (lib/stub/), the same install name with no class, which apps link.
# spec: README.md "Stand-in classes" -- an app links the stub weakly and binds each class flat and weak, after AppKit;
#       dyld's flat lookup then takes AppKit's class where AppKit has one and the stand-in's on 10.9
set -eu
umask 022
SELF=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
. "$SELF/lib.sh"
ROOT=$MAVERICKS_ROOT
[ "$#" = 2 ] || { sed -n 3,5p "$0" >&2; exit 2; }
T=$1; W=$2
case "$T:$W" in /*:/*) ;; *) echo 'build-standins: absolute stage/work paths required' >&2; exit 2 ;; esac
[ -n "${SDK:-}" ] || SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")
[ -f "$SDK/SDKSettings.plist" ] || { echo "build-standins: $SDK is not an SDK" >&2; exit 1; }
recaulk_tools
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
LIB=libRecaulkAppKit.dylib
NAME="@rpath/$LIB"

# spec: README.md "Stand-in classes" -- HOW each class is exported is this one step, swappable while Drydock settles it
#       (its modern check found dyld4 loading an on-disk dylib before the shared-cache AppKit, so a plain alias would
#       win over AppKit there, where a weak definition would not). STANDIN_EXPORT:
#         alias  (default) the linker's -alias to the AppKit names, the class's own names unexported;
#         rename  the object's class symbols renamed in place (llvm-objcopy --redefine-sym), the step a weak definition
#                 would extend: ld64.lld's -alias, an assembler .set and llvm-objcopy --weaken-symbol all leave the
#                 Mach-O symbol non-weak, so this toolchain gives no weak flag yet.
#       STANDIN_STUB=no stages no stub. The runtime name, the class's own, is the same either way.
STANDIN_EXPORT=${STANDIN_EXPORT:-alias}
STANDIN_STUB=${STANDIN_STUB:-yes}
standin_export() { # MINE THEIRS OBJECT: appends link flags to $W/link-flags, or rewrites OBJECT in place
  for kind in CLASS METACLASS; do
    case "$STANDIN_EXPORT" in
      alias)
        printf -- '-Wl,-alias,_OBJC_%s_$_%s,_OBJC_%s_$_%s\n' "$kind" "$1" "$kind" "$2" >> "$W/link-flags"
        printf -- '-Wl,-unexported_symbol,_OBJC_%s_$_%s\n' "$kind" "$1" >> "$W/link-flags" ;;
      rename)
        "$CL/bin/llvm-objcopy" --redefine-sym "_OBJC_${kind}_\$_$1=_OBJC_${kind}_\$_$2" "$3" ;;
      *) echo "build-standins: STANDIN_EXPORT is '$STANDIN_EXPORT': want alias or rename" >&2; exit 2 ;;
    esac
  done
}

rm -rf "$W"
mkdir -p "$W/objects" "$T/lib/stand-in"
"$CC" --version > "$W/compiler.txt"
printf 'SDK=%s\n' "$SDK" > "$W/sdk.txt"
: > "$W/link-flags"
: > "$W/source-inputs"
grep -v '^#' "$ROOT/build/standins.txt" | awk 'NF' | while read -r mine theirs; do
  [ -f "$ROOT/src/standins/$mine.m" ] || { echo "build-standins: build/standins.txt names $mine, with no src/standins/$mine.m" >&2; exit 1; }
  # spec: tests/objc-archive-reproducible.sh -- the same prefix maps as librecaulk-objc.a, for the same bytes anywhere
  "$CC" $TARGET_FLAGS -isysroot "$SDK" -fobjc-arc -Os -g -fPIC -Wall -Werror -Wno-deprecated-declarations \
    -ffile-prefix-map="$ROOT/"= -ffile-prefix-map="$W/"= \
    -ffile-prefix-map="$SDK"="$(basename "$SDK")" -fdebug-compilation-dir=. \
    -I"$ROOT/src/objc" -c "$ROOT/src/standins/$mine.m" -o "$W/objects/$mine.o"
  standin_export "$mine" "$theirs" "$W/objects/$mine.o"
  echo "src/standins/$mine.m" >> "$W/source-inputs"
done
# spec: README.md "Stand-in classes" -- the stand-in's own install name is what the stub carries, so an app built
#       against the stub loads the stand-in from its Frameworks directory. Drydock names each method by its local
#       symbol, so nothing here strips them.
# shellcheck disable=SC2046 # one link flag per line, none with spaces
"$CC" -dynamiclib $TARGET_FLAGS -isysroot "$SDK" -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -fobjc-arc \
  -o "$T/lib/stand-in/$LIB" "$W"/objects/*.o $(cat "$W/link-flags") \
  -install_name "$NAME" -compatibility_version 1.0.0 -current_version 1.0.0 \
  -framework AppKit -framework Foundation -lobjc
rm -rf "$T/lib/stub"
if [ "$STANDIN_STUB" = yes ]; then
  mkdir -p "$T/lib/stub"
  printf '/* the stub of %s: its install name, no class */\nint __recaulk_appkit_stub;\n' "$LIB" > "$W/stub.c"
  "$CC" $TARGET_FLAGS -isysroot "$SDK" -c "$W/stub.c" -o "$W/stub.o"
  "$CC" -dynamiclib $TARGET_FLAGS -isysroot "$SDK" -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" \
    -o "$T/lib/stub/$LIB" "$W/stub.o" -install_name "$NAME" -compatibility_version 1.0.0 -current_version 1.0.0
fi
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
(cd "$ROOT" && sha256 $(cat "$W/source-inputs") src/objc/accessibility-map.h build/standins.txt build/build-standins.sh) \
  > "$W/source-inputs.txt"
(cd "$T" && sha256 lib/stand-in/$LIB $([ "$STANDIN_STUB" = yes ] && echo lib/stub/$LIB)) > "$W/products.txt"
printf 'export=%s\nstub=%s\n' "$STANDIN_EXPORT" "$STANDIN_STUB" > "$W/export.txt"
