#!/bin/sh
# platform: macOS-only -- reads Mach-O stubs (.dylib/framework on 10.9, .tbd on a modern host) with nm

# platform: a .dylib or framework binary on 10.9 and a .tbd on a modern host are the same library; nm reads both
sdk_stub_exports() {
  for _se_base in "$@"; do
    if [ ! -f "$_se_base" ] && [ ! -f "$_se_base.dylib" ] && [ ! -f "$_se_base.tbd" ]; then
      echo "sdk_exports: warning: no library at $_se_base (.dylib, .tbd or bare)" >&2
    fi
    for _se_f in "$_se_base" "$_se_base.dylib" "$_se_base.tbd"; do
      if [ -f "$_se_f" ]; then
        "${NM:-nm}" -gU "$_se_f" | awk 'NF == 3 && $2 ~ /^[A-Za-z]$/ { print $3 }'
      fi
    done
  done
}

sdk_exports() {
  _se_sdk="$1"
  _se_fw="$_se_sdk/System/Library/Frameworks"
  {
    sdk_stub_exports "$_se_sdk/usr/lib/libSystem.B" "$_se_sdk/usr/lib/libobjc.A"
    for _se_f in "$_se_sdk"/usr/lib/system/*.dylib "$_se_sdk"/usr/lib/system/*.tbd; do
      [ -f "$_se_f" ] && sdk_stub_exports "$_se_f"
    done
    for _se_n in CoreFoundation Security CoreVideo CoreGraphics IOKit CoreServices; do
      sdk_stub_exports "$_se_fw/$_se_n.framework/$_se_n"
    done
    for _se_d in "$_se_fw"/CoreServices.framework/Frameworks/*.framework; do
      _se_n="$(basename "$_se_d" .framework)"
      sdk_stub_exports "$_se_d/$_se_n"
    done
  } | LC_ALL=C sort -u
}
