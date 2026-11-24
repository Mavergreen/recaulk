#!/bin/sh
# platform: host-agnostic
# spec: README.md "The kernel-fixes kext" -- 10.9's kextd loads an unsigned kext from /Library/Extensions only if its
#       bundle id is in OSKextSigExceptionList, in AppleKextExcludeList.kext's Info.plist (Wowfunhappy's mechanism,
#       gist ee66f57e5e7a04e42a7a5e2b98a10874). Apple ships that file as XML with one <key>/<string> pair per entry.
#   usage: kext-exception.sh add PLIST BUNDLE_ID VERSION   add the entry, or replace its version
#          kext-exception.sh remove PLIST BUNDLE_ID        remove it; absent is fine
# Every other byte stays; the file is replaced in one rename, mode 644. A plist that is not XML or has no
# OSKextSigExceptionList is refused and left alone.
set -eu
op="${1:-}"; P="${2:-}"; id="${3:-}"; ver="${4:-}"
case "$op" in
  add) [ -n "$id" ] && [ -n "$ver" ] || { echo "usage: kext-exception.sh add PLIST BUNDLE_ID VERSION" >&2; exit 2; } ;;
  remove) [ -n "$id" ] || { echo "usage: kext-exception.sh remove PLIST BUNDLE_ID" >&2; exit 2; } ;;
  *) echo "usage: kext-exception.sh add|remove PLIST BUNDLE_ID [VERSION]" >&2; exit 2 ;;
esac
[ -f "$P" ] || { echo "kext-exception: no $P" >&2; exit 1; }
head -c 5 "$P" | grep -q '^<?xml' || { echo "kext-exception: $P is not an XML plist; left alone" >&2; exit 1; }
tmp="$P.recaulk.$$"
trap 'rm -f "$tmp"' EXIT
awk -v op="$op" -v id="$id" -v ver="$ver" '
  inlist && skip { skip = 0; next }
  inlist && index($0, "<key>" id "</key>") { skip = 1; next }
  inlist && /<\/dict>/ { inlist = 0 }
  { print }
  want && /<dict>/ {
    want = 0; inlist = 1; found = 1
    if (op == "add") { print "\t\t<key>" id "</key>"; print "\t\t<string>" ver "</string>" }
  }
  /<key>OSKextSigExceptionList<\/key>/ { want = 1 }
  END { if (!found) exit 3 }
' "$P" > "$tmp" || { echo "kext-exception: $P has no OSKextSigExceptionList; left alone" >&2; exit 1; }
# platform: Apple's file is 644 root:wheel; the installer runs this as root, so the new file is root's too
chmod 644 "$tmp"
mv -f "$tmp" "$P"
trap - EXIT
