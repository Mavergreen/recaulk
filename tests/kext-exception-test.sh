#!/bin/sh
# platform: host-agnostic
# spec: README.md "The kernel-fixes kext" -- 10.9's kextd loads an unsigned kext from /Library/Extensions only if its
#       bundle id is in OSKextSigExceptionList (AppleKextExcludeList.kext's Info.plist, XML). kext-exception.sh adds
#       or replaces one entry, and removes it, leaving every other byte of Apple's file as it was.
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/kext-exception.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
X="$R/packaging/kext-exception.sh"
ID=dev.mavergreen.recaulk.kernelfixes
P="$t/Info.plist"
tab="$(printf '\t')"
cat > "$t/orig" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${tab}<key>OSKextExcludeList</key>
${tab}<dict>
${tab}${tab}<key>com.example.excluded</key>
${tab}${tab}<string>1.0</string>
${tab}</dict>
${tab}<key>OSKextSigExceptionList</key>
${tab}<dict>
${tab}${tab}<key>Astrill</key>
${tab}${tab}<string>1.0</string>
${tab}${tab}<key>anon.tap</key>
${tab}${tab}<string>1.0</string>
${tab}</dict>
</dict>
</plist>
EOF
entries() { awk -v id="$ID" 'index($0, "<key>" id "</key>") { n++; getline; v = v $0 } END { print n + 0, v }' "$P"; }

echo "== add"
cp "$t/orig" "$P"
sh "$X" add "$P" "$ID" 2611.23.4 || bad "add failed"
[ "$(entries)" = "1 ${tab}${tab}<string>2611.23.4</string>" ] || bad "add: want one entry at 2611.23.4, got: $(entries)"
awk '/OSKextExcludeList/,/<\/dict>/' "$P" | grep -q "$ID" && bad "add: the entry went into OSKextExcludeList"
grep -v -e "<key>$ID</key>" -e '<string>2611.23.4</string>' "$P" | cmp -s - "$t/orig" || bad "add changed other lines"

echo "== replace"
sh "$X" add "$P" "$ID" 2612.1.1 || bad "replace failed"
[ "$(entries)" = "1 ${tab}${tab}<string>2612.1.1</string>" ] || bad "replace: want one entry at 2612.1.1, got: $(entries)"

echo "== remove"
sh "$X" remove "$P" "$ID" || bad "remove failed"
cmp -s "$P" "$t/orig" || bad "remove did not restore Apple's file byte for byte"
sh "$X" remove "$P" "$ID" || bad "removing an absent entry must succeed"
cmp -s "$P" "$t/orig" || bad "removing an absent entry changed the file"

echo "== refusals"
printf 'bplist00binary' > "$P"
if sh "$X" add "$P" "$ID" 1.0 2>/dev/null; then bad "a binary plist was edited"; fi
[ "$(cat "$P")" = bplist00binary ] || bad "a refused binary plist changed"
grep -v OSKextSigExceptionList "$t/orig" > "$P"; cp "$P" "$t/nolist"
if sh "$X" add "$P" "$ID" 1.0 2>/dev/null; then bad "a plist without OSKextSigExceptionList was edited"; fi
cmp -s "$P" "$t/nolist" || bad "a refused plist without the list changed"
if sh "$X" add "$t/absent" "$ID" 1.0 2>/dev/null; then bad "a missing plist reported success"; fi

[ "$fail" = 0 ] && echo "kext-exception OK"
exit "$fail"
