#!/bin/sh
# platform: host-agnostic
#   usage: objc-provider-manifest.sh header DECL OUT
#          objc-provider-manifest.sh manifest DECL ARCHIVE OUT ARCH ROLE SDK_SETTINGS COMPILER_RECEIPT SOURCE_RECEIPT
#          checks DECL against the providers Recaulk ships and against the encoding clang22 compiles for each
#          one's declaration, then writes the generated header or the provider manifest. Needs CC, TARGET_FLAGS, SDK and
#          LIPO in the environment (build/lib.sh recaulk_tools).
set -eu
die() { echo "objc-provider-manifest: $*" >&2; exit 1; }
[ "$#" -ge 3 ] || { sed -n 3,7p "$0" >&2; exit 2; }
mode=$1 decl=$2
: "${CC:?}" "${TARGET_FLAGS:?}" "${SDK:?}"

# spec: README.md "Objective-C methods" -- each provider Recaulk ships, one per line, tab-separated:
#       macro id class kind selector encoding implementation root frameworks(comma-separated)
providers() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    WORKSPACE recaulk.nsworkspace.open-urls.v1 NSWorkspace - \
    'openURLs:withApplicationAtURL:options:configuration:error:' '@56@0:8@16@24Q32@40^@48' \
    __recaulk_objc_workspace_open_urls __recaulk_objc_activate AppKit,Carbon \
    WORKSPACE_VOICEOVER recaulk.nsworkspace.is-voiceover-enabled.v1 NSWorkspace - isVoiceOverEnabled 'c16@0:8' \
    __recaulk_objc_workspace_is_voiceover_enabled __recaulk_objc_activate AppKit,Carbon \
    WORKSPACE_REDUCE_MOTION recaulk.nsworkspace.should-reduce-motion.v1 NSWorkspace - \
    accessibilityDisplayShouldReduceMotion 'c16@0:8' \
    __recaulk_objc_workspace_should_reduce_motion __recaulk_objc_activate AppKit,Carbon \
    LOCALE_LANGUAGE_CODE recaulk.nslocale.language-code.v1 NSLocale - languageCode '@16@0:8' \
    __recaulk_objc_locale_language_code __recaulk_objc_activate_foundation Foundation \
    LOCALE_COUNTRY_CODE recaulk.nslocale.country-code.v1 NSLocale - countryCode '@16@0:8' \
    __recaulk_objc_locale_country_code __recaulk_objc_activate_foundation Foundation
}
# spec: README.md "Objective-C methods" -- each provider's method declared, compiled to measure clang22's encoding for it
probe_source() {
  case "$1" in
    recaulk.nsworkspace.open-urls.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@class NSRunningApplication;
@interface RecaulkProviderEncoding : NSObject
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSUInteger)o configuration:(NSDictionary *)c error:(NSError **)e;
@end
@implementation RecaulkProviderEncoding
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSUInteger)o configuration:(NSDictionary *)c error:(NSError **)e { return nil; }
@end
EOF
    ;;
    recaulk.nsworkspace.is-voiceover-enabled.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (BOOL)isVoiceOverEnabled;
@end
@implementation RecaulkProviderEncoding
- (BOOL)isVoiceOverEnabled { return NO; }
@end
EOF
    ;;
    recaulk.nsworkspace.should-reduce-motion.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (BOOL)accessibilityDisplayShouldReduceMotion;
@end
@implementation RecaulkProviderEncoding
- (BOOL)accessibilityDisplayShouldReduceMotion { return NO; }
@end
EOF
    ;;
    recaulk.nslocale.language-code.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSString *)languageCode;
@end
@implementation RecaulkProviderEncoding
- (NSString *)languageCode { return nil; }
@end
EOF
    ;;
    recaulk.nslocale.country-code.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSString *)countryCode;
@end
@implementation RecaulkProviderEncoding
- (NSString *)countryCode { return nil; }
@end
EOF
    ;;
    *) die "InvalidDeclaration: no encoding probe for provider $1" ;;
  esac
}
expected=$(providers | awk -F'\t' 'BEGIN { printf "{\"schema\":1,\"providers\":[" }
  { split($9, f, ","); fw = ""; for (i = 1; i in f; i++) fw = fw (i > 1 ? "," : "") "\"" f[i] "\""
    printf "%s{\"provider_id\":\"%s\",\"class\":\"%s\",\"method_kind\":\"%s\",\"selector\":\"%s\",\"encoding\":\"%s\",\"implementation_symbol\":\"%s\",\"activation_root\":\"%s\",\"required_frameworks\":[%s],\"framework_policy\":\"strong-linked-before-root\"}", (NR > 1 ? "," : ""), $2, $3, $4, $5, $6, $7, $8, fw }
  END { printf "]}" }')
[ -f "$decl" ] || die "InvalidDeclaration: $decl is missing"
[ "$(tr -d ' \t\r\n' < "$decl")" = "$expected" ] \
  || die "InvalidDeclaration: $decl is not the providers Recaulk ships (schema 1; build/objc-provider-manifest.sh lists them, each strong-linked-before-root)"

probe=$(mktemp -d "${TMPDIR:-/tmp}/objc-provider-manifest.XXXXXX")
trap 'rm -rf "$probe"' EXIT
providers > "$probe/providers.tsv"
while IFS='	' read -r macro id class kind selector encoding impl root frameworks; do
  probe_source "$id" > "$probe/$id.m"
  "$CC" $TARGET_FLAGS -isysroot "$SDK" -fno-objc-arc -S -o "$probe/$id.s" "$probe/$id.m" \
    || die "CannotMeasure: clang22 could not compile the encoding probe for $id"
  compiled=$(awk '/^[ \t]*\.section[ \t]/ { m = ($0 ~ /__objc_methtype/) } m && /\.asciz/ { sub(/^[^"]*"/, ""); sub(/"[^"]*$/, ""); print }' "$probe/$id.s")
  [ "$compiled" = "$encoding" ] \
    || die "InvalidDeclaration: $id's declared encoding $encoding is not the compiled one, '$compiled'"
done < "$probe/providers.tsv"

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
      while IFS='	' read -r macro id class kind selector encoding impl root frameworks; do
        printf '#define RECAULK_%s_CLASS "%s"\n' "$macro" "$class"
        printf '#define RECAULK_%s_SELECTOR "%s"\n' "$macro" "$selector"
        printf '#define RECAULK_%s_ENCODING "%s"\n' "$macro" "$encoding"
      done < "$probe/providers.tsv"
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
      printf '{\n  "schema" : 1,\n  "providers" : [\n'
      n=0
      while IFS='	' read -r macro id class kind selector encoding impl root frameworks; do
        [ "$n" = 0 ] || printf '    },\n'
        n=$((n + 1))
        printf '    {\n      "provider_id" : "%s",\n' "$id"
        printf '      "class" : "%s",\n      "method_kind" : "%s",\n' "$class" "$kind"
        printf '      "selector" : "%s",\n      "encoding" : "%s",\n' "$selector" "$encoding"
        printf '      "implementation_symbol" : "%s",\n' "$impl"
        printf '      "activation_root" : "%s",\n' "$root"
        printf '      "required_frameworks" : [\n'
        printf '%s\n' "$frameworks" | tr ',' '\n' | awk '{ printf "%s        \"%s\"", (NR > 1 ? ",\n" : ""), $0 } END { print "" }'
        printf '      ],\n'
        printf '      "framework_policy" : "strong-linked-before-root"\n'
      done < "$probe/providers.tsv"
      printf '    }\n  ],\n'
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
