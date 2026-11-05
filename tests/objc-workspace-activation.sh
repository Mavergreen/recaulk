#!/bin/sh
# platform: macOS-only -- real ordinary/dead-strip/LTO archive activation, no app launch
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
[ -f "$ROOT/build/build-objc.sh" ] || { echo 'FAIL: separate objc companion builder absent'; exit 1; }
: "${SHIPYARD_SCRIPTS:?set pinned shipyard scripts}"
[ -z "${DYLD_INSERT_LIBRARIES:-}${DYLD_FRAMEWORK_PATH:-}${DYLD_LIBRARY_PATH:-}" ] || { echo 'FAIL: injected runtime inputs cannot establish activation evidence'; exit 1; }
CP=${RECAULK_C_PREFIX:-${RECAULK_BUILD:-/not-configured}/stage/usr/local/mavergreen/recaulk}
# Objective-C activation (plain/dead-strip/LTO, ABI, weak owner) needs no C
# stage and always runs; only the C-isolation checks need the real C outputs.
c_measured=1
if [ ! -f "$CP/lib/librecaulk.a" ] || [ ! -f "$CP/lib/libRecaulkSystem.dylib" ]; then c_measured=0; fi
if [ -n "${RECAULK_OBJC_ACTIVATION_REPORT:-}" ]; then D=$RECAULK_OBJC_ACTIVATION_REPORT; case "$D" in /*) ;; *) exit 2 ;; esac; mkdir -m 700 "$D"; else D=$(mktemp -d "${TMPDIR:-/tmp}/workspace-activation.XXXXXX"); fi
# Preserve actual objects/binaries/logs as evidence; never remove caller output.
case "$(uname -m)" in arm64) arch=arm64; floor=11.0 ;; x86_64) arch=x86_64; floor=10.9 ;; *) exit 1 ;; esac
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$arch")
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT MACOSX_DEPLOYMENT_TARGET CCC_OVERRIDE_OPTIONS
if [ "$c_measured" = 1 ]; then shasum -a 256 "$CP/lib/librecaulk.a" "$CP/lib/libRecaulkSystem.dylib" > "$D/c-before.sha256"; fi
SDK="$SDK" HOST_SDK="$SDK" sh "$ROOT/build/build-objc.sh" "$D/stage" "$D/work" --native-test > "$D/builder.log" 2>&1
if [ "$c_measured" = 1 ]; then shasum -a 256 -c "$D/c-before.sha256" > "$D/c-after.log"; fi
A="$D/stage/lib/librecaulk-objc.a"
[ -f "$D/stage/share/recaulk/objc-providers.json" ]
/usr/bin/otool -L "$D/work/objc-provider-manifest" > "$D/generator-loads.txt"
! grep -q AppKit "$D/generator-loads.txt"
/usr/bin/nm -u "$D/work/objects/register.o" > "$D/register-imports.txt"
! grep -q objc_msgSend "$D/register-imports.txt"
# Reject declaration changes before producing registration constants.
awk '{sub(/"schema": 1/,"\"schema\": true"); print}' "$ROOT/src/objc/providers.json" > "$D/boolean-schema.json"
if "$D/work/objc-provider-manifest" header "$D/boolean-schema.json" "$D/bad-header.h" > "$D/bad-schema.log" 2>&1; then echo 'FAIL: boolean schema accepted as integer1'; exit 1; fi
[ ! -f "$D/bad-header.h" ]
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -c "$ROOT/tests/c/objc_workspace_activation.m" -o "$D/consumer.o"
strong_frameworks() {
 /usr/bin/otool -l "$1" > "$D/load-commands.txt"
 for framework in AppKit Carbon; do
  awk -v f="/$framework.framework/" '$1=="cmd" {cmd=$2} $1=="name" && index($2,f) {found=1;if(cmd!="LC_LOAD_DYLIB")bad=1} END{exit(!found || bad)}' "$D/load-commands.txt" || return 1
 done
}
for mode in plain dead-strip lto; do
 obj="$D/consumer.o"; extra=
 if [ "$mode" = dead-strip ]; then extra=-Wl,-dead_strip; fi
 if [ "$mode" = lto ]; then
  # Pin the native compiler's paired linker for THIS run, including its bytes.
  linker=$(/usr/bin/clang -print-prog-name=ld)
  case "$linker" in /usr/bin/ld|/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld|/Library/Developer/CommandLineTools/usr/bin/ld) ;; *) echo 'FAIL: unexpected LTO linker outside Apple toolchain'; exit 1 ;; esac
  shasum -a 256 "$linker" > "$D/lto-linker.sha256"
  "$linker" -v > "$D/lto-linker-version.txt" 2>&1 || :
  /usr/bin/clang --version > "$D/lto-compiler-version.txt"
  /usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" -fno-objc-arc -flto -c "$ROOT/tests/c/objc_workspace_activation.m" -o "$D/consumer-lto.o"
  magic=$(od -An -tx1 -N4 "$D/consumer-lto.o" | tr -d ' \n')
  case "$magic" in 4243c0de|dec0170b) ;; *) echo 'FAIL: consumer LTO input is not measured bitcode'; exit 1 ;; esac
  obj="$D/consumer-lto.o"; extra='-flto -Wl,-dead_strip'
 fi
 # Deliberate unquoted expansion: fixed compiler flags only, never user input.
 /usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" $extra "$obj" "$A" -framework AppKit -framework Carbon -o "$D/$mode-unrooted"
 "$D/$mode-unrooted" 0
 /usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" $extra "$obj" "$A" -Wl,-u,___recaulk_objc_activate -framework AppKit -framework Carbon -o "$D/$mode-rooted"
 strong_frameworks "$D/$mode-rooted"
 "$D/$mode-rooted" 1
 if [ "$mode" = lto ]; then shasum -a 256 -c "$D/lto-linker.sha256"; fi
done
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" "$D/consumer.o" "$A" -Wl,-u,___recaulk_objc_activate -weak_framework AppKit -framework Carbon -o "$D/weak-owner"
if strong_frameworks "$D/weak-owner"; then echo 'FAIL: weak owner accepted as strong provider policy'; exit 1; fi
# A plain C native consumer must not acquire the unrooted companion or AppKit.
printf '%s\n' '#include <mach-o/dyld.h>' '#include <string.h>' 'int main(void){for(unsigned i=0;i<_dyld_image_count();i++)if(strstr(_dyld_get_image_name(i),"/AppKit.framework/"))return 1;return 0;}' > "$D/ordinary.c"
/usr/bin/clang -arch "$arch" -isysroot "$SDK" -mmacosx-version-min="$floor" "$D/ordinary.c" "$A" -o "$D/ordinary"
"$D/ordinary"
/usr/bin/nm "$D/ordinary" > "$D/ordinary-symbols.txt"
! grep -q __recaulk_objc_activate "$D/ordinary-symbols.txt"
if [ "$c_measured" = 0 ]; then
 echo "PASS: actual root in ordinary/dead-strip/LTO; inherited/native/ABI preserved; weak owner rejected by policy. Evidence: $D"
 echo 'SKIP: actual C archive/dylib required for C isolation checks; not measured'
 exit 77
fi
/usr/bin/nm "$CP/lib/librecaulk.a" > "$D/c-archive-symbols.txt"
/usr/bin/nm "$CP/lib/libRecaulkSystem.dylib" > "$D/c-dylib-symbols.txt"
/usr/bin/otool -L "$CP/lib/libRecaulkSystem.dylib" > "$D/c-dylib-loads.txt"
! grep -q __recaulk_objc "$D/c-archive-symbols.txt"
! grep -q __recaulk_objc "$D/c-dylib-symbols.txt"
! grep -q AppKit "$D/c-dylib-loads.txt"
# Also link the ACTUAL shipping C archive, rather than a placeholder. On arm64
# this is a cross artifact inspection, never a Rosetta installation/request.
printf '%s\n' '#include <stddef.h>' 'extern int getentropy(void *,size_t);' '#include <mach-o/dyld.h>' '#include <string.h>' 'int main(void){unsigned char b;if(getentropy(&b,1))return 1;for(unsigned i=0;i<_dyld_image_count();i++)if(strstr(_dyld_get_image_name(i),"/AppKit.framework/"))return 1;return 0;}' > "$D/actual-c.c"
CSDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
/usr/bin/clang -arch x86_64 -isysroot "$CSDK" -mmacosx-version-min=10.9 "$D/actual-c.c" "$CP/lib/librecaulk.a" -framework CoreFoundation -framework Security -framework CoreVideo -framework CoreGraphics -framework CoreServices -lobjc -lc++abi -o "$D/actual-c"
/usr/bin/otool -L "$D/actual-c" > "$D/actual-c-loads.txt"
! grep -q AppKit "$D/actual-c-loads.txt"
if [ "$arch" = x86_64 ]; then "$D/actual-c"; fi
printf 'PASS: actual root in ordinary/dead-strip/LTO; inherited/native/ABI preserved; weak owner rejected by policy; C outputs unchanged. Evidence: %s\n' "$D"
