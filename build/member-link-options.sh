#!/bin/sh
# platform: host-agnostic
# spec: README.md "How to use" -- each librecaulk.a member carries, as LC_LINKER_OPTION, the frameworks and libraries
#       its own undefined symbols come from, so a force-load needs no flags and a normal link gains nothing unused.
#   usage: member-link-options.sh map SDK          prints "symbol<TAB>option" for each export of the SDK libraries
#                                                  beyond libSystem a member may use
#          member-link-options.sh options MAP OBJ  prints the options OBJ needs, one per line, in a fixed order
#          member-link-options.sh header MAP OBJ   prints a C header carrying them as .linker_option directives
set -eu
NM="${NM:-nm}"
stub() { # option path-without-extension
  for _s_f in "$2" "$2.dylib" "$2.tbd"; do
    [ -f "$_s_f" ] || continue
    "$NM" -gU "$_s_f" | awk -v o="$1" 'NF == 3 && $2 ~ /^[A-Za-z]$/ { print $3 "\t" o }'
  done
  return 0
}
case "${1:-}" in
  map)
    sdk="$2"; fw="$sdk/System/Library/Frameworks"
    {
      stub "-lobjc" "$sdk/usr/lib/libobjc.A"
      stub "-lc++abi" "$sdk/usr/lib/libc++abi"
      for n in CoreFoundation Security CoreGraphics CoreServices CoreVideo IOKit; do
        stub "-framework $n" "$fw/$n.framework/$n"
      done
      for d in "$fw"/CoreServices.framework/Frameworks/*.framework; do
        stub "-framework CoreServices" "$d/$(basename "$d" .framework)"
      done
    } | awk -F'\t' '!seen[$1]++'
    ;;
  options)
    "$NM" -u "$3" | awk '{ print $NF }' | LC_ALL=C sort -u \
      | awk -F'\t' 'FILENAME == ARGV[1] { o[$1] = $2; next } $1 in o { print o[$1] }' "$2" - | LC_ALL=C sort -u
    ;;
  header)
    sh "$0" options "$2" "$3" | awk '{
      if ($1 == "-framework") printf "__asm__(\".linker_option \\\"-framework\\\", \\\"%s\\\"\");\n", $2
      else printf "__asm__(\".linker_option \\\"%s\\\"\");\n", $1
    }'
    ;;
  *) echo "usage: member-link-options.sh map SDK | options MAP OBJ | header MAP OBJ" >&2; exit 2 ;;
esac
