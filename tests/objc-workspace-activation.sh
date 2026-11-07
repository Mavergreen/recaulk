#!/bin/sh
# platform: host-agnostic -- links consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C provider" -- the provider activates only in a program that roots
#       __recaulk_objc_activate (plain, dead-strip and LTO links alike), strong-links AppKit and Carbon
#       when rooted, and never reaches a C-only consumer or librecaulk.a/libRecaulkSystem.dylib.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
fail=0
bad() { echo "FAIL: $*"; fail=1; }
A="$T/lib/librecaulk-objc.a"

if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  D="$(dirname "$(tbin x)")"
  "$NM" -u "$W/objc-companion/objects/register.o" > "$D/register-imports.txt"
  if grep -q objc_msgSend "$D/register-imports.txt"; then bad "register.o sends messages; registration must use the runtime's C API only"; fi
  awk '{ sub(/"schema": 1/, "\"schema\": true"); print }' src/objc/providers.json > "$D/boolean-schema.json"
  if CC="$CC" TARGET_FLAGS="$TARGET_FLAGS" SDK="$SDK" sh build/objc-provider-manifest.sh header "$D/boolean-schema.json" "$D/bad-header.h" > "$D/bad-schema.log" 2>&1; then
    bad "the manifest generator accepted a boolean schema as the integer 1"
  fi
  [ ! -f "$D/bad-header.h" ] || bad "a refused declaration still produced a header"

  "$CC" $FLAGS -fno-objc-arc -c tests/c/objc_workspace_activation.m -o "$D/consumer.o"
  "$CC" $FLAGS -fno-objc-arc -flto -c tests/c/objc_workspace_activation.m -o "$D/consumer-lto.o"
  case "$(od -An -tx1 -N4 "$D/consumer-lto.o" | tr -d ' \n')" in
    4243c0de|dec0170b) ;;
    *) bad "the LTO consumer object is not bitcode, so the LTO link proves nothing" ;;
  esac
  strong_frameworks() {
    "$OTOOL" -l "$1" > "$1.loads"
    for _f in AppKit Carbon; do
      awk -v f="/$_f.framework/" '$1 == "cmd" { cmd = $2 }
        $1 == "name" && index($2, f) { found = 1; if (cmd != "LC_LOAD_DYLIB") weak = 1 }
        END { exit(!found || weak) }' "$1.loads" || return 1
    done
  }
  for mode in plain dead-strip lto; do
    obj="$D/consumer.o"; extra=
    case "$mode" in
      dead-strip) extra=-Wl,-dead_strip ;;
      lto) obj="$D/consumer-lto.o"; extra='-flto -Wl,-dead_strip' ;;
    esac
    "$CC" $FLAGS $extra "$obj" "$A" -framework AppKit -framework Carbon -o "$(tbin "$mode-unrooted")"
    "$CC" $FLAGS $extra "$obj" "$A" -Wl,-u,___recaulk_objc_activate -framework AppKit -framework Carbon \
      -o "$(tbin "$mode-rooted")"
    strong_frameworks "$(tbin "$mode-rooted")" || bad "$mode-rooted does not strong-link AppKit and Carbon"
    check_loads "$(tbin "$mode-unrooted")" "$(tbin "$mode-rooted")" || fail=1
  done
  "$CC" $FLAGS "$D/consumer.o" "$A" -Wl,-u,___recaulk_objc_activate -weak_framework AppKit -framework Carbon \
    -o "$D/weak-owner"
  if strong_frameworks "$D/weak-owner"; then bad "a weak AppKit owner passed the strong-link check"; fi

  printf '%s\n' '#include <mach-o/dyld.h>' '#include <string.h>' \
    'int main(void){for(unsigned i=0;i<_dyld_image_count();i++)if(strstr(_dyld_get_image_name(i),"/AppKit.framework/"))return 1;return 0;}' \
    > "$D/ordinary.c"
  "$CC" $FLAGS "$D/ordinary.c" "$A" -o "$(tbin ordinary)"
  if "$NM" "$(tbin ordinary)" | grep -q __recaulk_objc_activate; then bad "a C-only consumer linked the provider"; fi

  if "$NM" "$T/lib/librecaulk.a" 2>/dev/null | grep -q __recaulk_objc; then bad "librecaulk.a carries provider symbols"; fi
  if "$NM" "$T/lib/libRecaulkSystem.dylib" | grep -q __recaulk_objc; then bad "libRecaulkSystem.dylib carries provider symbols"; fi
  if "$OTOOL" -L "$T/lib/libRecaulkSystem.dylib" | grep -q AppKit; then bad "libRecaulkSystem.dylib loads AppKit"; fi
  printf '%s\n' '#include <stddef.h>' 'extern int getentropy(void *,size_t);' '#include <mach-o/dyld.h>' '#include <string.h>' \
    'int main(void){unsigned char b;if(getentropy(&b,1))return 1;for(unsigned i=0;i<_dyld_image_count();i++)if(strstr(_dyld_get_image_name(i),"/AppKit.framework/"))return 1;return 0;}' \
    > "$D/actual-c.c"
  "$CC" $FLAGS "$D/actual-c.c" "$T/lib/librecaulk.a" -framework CoreFoundation -framework Security \
    -framework CoreVideo -framework CoreGraphics -framework CoreServices -lobjc -lc++abi -o "$(tbin actual-c)"
  if "$OTOOL" -L "$(tbin actual-c)" | grep -q AppKit; then bad "a librecaulk.a consumer loads AppKit"; fi
  check_loads "$(tbin ordinary)" "$(tbin actual-c)" || fail=1
  [ "$fail" = 0 ] || exit 1
fi
runtime_half
for mode in plain dead-strip lto; do
  "$(tbin "$mode-unrooted")" 0 || bad "$mode-unrooted: the provider activated without its root"
  "$(tbin "$mode-rooted")" 1 || bad "$mode-rooted: the rooted provider did not activate"
done
"$(tbin ordinary)" || bad "a C-only consumer of librecaulk-objc.a loaded AppKit"
"$(tbin actual-c)" || bad "a librecaulk.a consumer loaded AppKit or failed getentropy"
[ "$fail" = 0 ] && echo "objc-workspace-activation OK"
exit $fail
