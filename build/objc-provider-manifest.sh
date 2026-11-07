#!/bin/sh
# platform: host-agnostic
#   usage: objc-provider-manifest.sh header DECL OUT
#          objc-provider-manifest.sh manifest DECL ARCHIVE OUT ARCH ROLE SDK_SETTINGS COMPILER_RECEIPT SOURCE_RECEIPT
#          checks DECL against the one provider Recaulk ships and against the encoding clang22 compiles for its
#          declaration, then writes the generated header or the provider manifest. Needs CC, TARGET_FLAGS, SDK and
#          LIPO in the environment (build/lib.sh recaulk_tools).
set -eu
die() { echo "objc-provider-manifest: $*" >&2; exit 1; }
[ "$#" -ge 3 ] || { sed -n 3,7p "$0" >&2; exit 2; }
mode=$1 decl=$2
: "${CC:?}" "${TARGET_FLAGS:?}" "${SDK:?}"

expected='{"schema":1,"providers":[{"provider_id":"recaulk.nsworkspace.open-urls.v1","class":"NSWorkspace","method_kind":"-","selector":"openURLs:withApplicationAtURL:options:configuration:error:","encoding":"@56@0:8@16@24Q32@40^@48","implementation_symbol":"__recaulk_objc_workspace_open_urls","activation_root":"__recaulk_objc_activate","required_frameworks":["AppKit","Carbon"],"framework_policy":"strong-linked-before-root"}]}'
[ -f "$decl" ] || die "InvalidDeclaration: $decl is missing"
[ "$(tr -d ' \t\r\n' < "$decl")" = "$expected" ] \
  || die "InvalidDeclaration: $decl is not the one provider Recaulk ships (schema 1, NSWorkspace openURLs, strong-linked-before-root)"
class=NSWorkspace
selector='openURLs:withApplicationAtURL:options:configuration:error:'
encoding='@56@0:8@16@24Q32@40^@48'

probe=$(mktemp -d "${TMPDIR:-/tmp}/objc-provider-manifest.XXXXXX")
trap 'rm -rf "$probe"' EXIT
cat > "$probe/encoding.m" <<'EOF'
#import <Foundation/Foundation.h>
@class NSRunningApplication;
@interface RecaulkProviderEncoding : NSObject
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSUInteger)o configuration:(NSDictionary *)c error:(NSError **)e;
@end
@implementation RecaulkProviderEncoding
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSUInteger)o configuration:(NSDictionary *)c error:(NSError **)e { return nil; }
@end
EOF
"$CC" $TARGET_FLAGS -isysroot "$SDK" -fno-objc-arc -S -o "$probe/encoding.s" "$probe/encoding.m" \
  || die "CannotMeasure: clang22 could not compile the encoding probe"
compiled=$(awk '/^[ \t]*\.section[ \t]/ { m = ($0 ~ /__objc_methtype/) } m && /\.asciz/ { sub(/^[^"]*"/, ""); sub(/"[^"]*$/, ""); print }' "$probe/encoding.s")
[ "$compiled" = "$encoding" ] \
  || die "InvalidDeclaration: the declared encoding $encoding is not the compiled one, '$compiled'"

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
json_string() {
  awk 'BEGIN { ORS = "" }
       { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "\\r")
         if (NR > 1) print "\\n"; print }
       END { if (NR > 0) print "\\n" }' "$1"
}

case "$mode:$#" in
  header:3)
    {
      printf '/* Generated from checked declaration; compiled ABI verified. */\n'
      printf '#define RECAULK_WORKSPACE_CLASS "%s"\n' "$class"
      printf '#define RECAULK_WORKSPACE_SELECTOR "%s"\n' "$selector"
      printf '#define RECAULK_WORKSPACE_ENCODING "%s"\n' "$encoding"
    } > "$3.tmp" && mv "$3.tmp" "$3"
    ;;
  manifest:9)
    archive=$3 out=$4 arch=$5 role=$6 settings=$7 compiler=$8 sources=$9
    : "${LIPO:?}"
    case "$arch:$role" in x86_64:shipping|x86_64:native-test-only|arm64:native-test-only) ;;
      *) die "CannotMeasure: arch $arch and role $role are not a combination Recaulk builds" ;; esac
    actual=$("$LIPO" -archs "$archive" 2>/dev/null) || die "CannotMeasure: cannot read $archive's architectures"
    [ "$actual" = "$arch" ] || die "CannotMeasure: $archive is '$actual', not $arch"
    [ -s "$compiler" ] && [ -s "$sources" ] && [ -f "$settings" ] || die "CannotMeasure: build evidence missing"
    case "$arch" in arm64) minimum=11.0 ;; *) minimum=10.9 ;; esac
    {
      printf '{\n  "schema" : 1,\n  "providers" : [\n    {\n'
      printf '      "provider_id" : "recaulk.nsworkspace.open-urls.v1",\n'
      printf '      "class" : "%s",\n      "method_kind" : "-",\n' "$class"
      printf '      "selector" : "%s",\n      "encoding" : "%s",\n' "$selector" "$encoding"
      printf '      "implementation_symbol" : "__recaulk_objc_workspace_open_urls",\n'
      printf '      "activation_root" : "__recaulk_objc_activate",\n'
      printf '      "required_frameworks" : [\n        "AppKit",\n        "Carbon"\n      ],\n'
      printf '      "framework_policy" : "strong-linked-before-root"\n    }\n  ],\n'
      printf '  "build" : {\n'
      printf '    "archive_path" : "lib/librecaulk-objc.a",\n'
      printf '    "archive_sha256" : "%s",\n' "$(sha256 "$archive")"
      printf '    "architecture" : "%s",\n' "$actual"
      printf '    "artifact_role" : "%s",\n' "$role"
      printf '    "minimum_macos" : "%s",\n' "$minimum"
      printf '    "sdk_settings_sha256" : "%s",\n' "$(sha256 "$settings")"
      printf '    "compiler_identity" : "%s",\n' "$(json_string "$compiler")"
      printf '    "source_inputs_receipt" : "%s",\n' "$(json_string "$sources")"
      printf '    "source_inputs_sha256" : "%s"\n' "$(sha256 "$sources")"
      printf '  }\n}\n'
    } > "$out.tmp" && mv "$out.tmp" "$out"
    ;;
  *) sed -n 3,7p "$0" >&2; exit 2 ;;
esac
