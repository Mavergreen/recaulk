#!/bin/sh
# platform: macOS-only -- builds the shipping x86_64/10.9 companion and its source receipt with the pinned clang
# spec: build/build-objc.sh header -- a shipping stage carries share/recaulk/objc-source.receipt beside
#       objc-providers.json: shipyard's objc-source-inventory.sh receipt of exactly the prepared source the
#       archive was built from, so a consumer's analysis can close the provider body's own sends.
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
: "${SHIPYARD_SCRIPTS:?set pinned shipyard scripts}"
fail() { echo "FAIL: $*"; exit 1; }
D=$(mktemp -d "${TMPDIR:-/tmp}/objc-source-receipt.XXXXXX")
D=$(cd "$D" && pwd -P)
trap 'rm -rf "$D"' EXIT
sh "$ROOT/build/build-objc.sh" "$D/stage" "$D/work" > "$D/builder.log" 2>&1 || { tail -20 "$D/builder.log"; fail 'companion build'; }
R="$D/stage/share/recaulk/objc-source.receipt"
[ -f "$R" ] || fail 'the stage has no share/recaulk/objc-source.receipt'
[ "$(sed -n 1p "$R")" = '# objc-source-receipt 1' ] || fail "the receipt's first line is $(sed -n 1p "$R")"
grep '^profile	recaulk-objc-x86_64-10.9$' "$R" >/dev/null || fail 'the receipt is not for the x86_64 10.9 profile'
# Every prepared input the archive's declaration lists is an input of the receipt, with the same digest.
while read -r sha label; do
  grep -Fx "$(printf 'input\t%s\t%s' "$label" "$sha")" "$R" >/dev/null || fail "the receipt does not record $label at $sha"
done < "$D/work/source-inputs.txt"
# A native-test stage is never shipped, so it carries no receipt.
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$(uname -m)")
SDK="$SDK" HOST_SDK="$SDK" sh "$ROOT/build/build-objc.sh" "$D/native" "$D/native-work" --native-test > "$D/native.log" 2>&1 || fail 'native-test build'
[ ! -e "$D/native/share/recaulk/objc-source.receipt" ] || fail 'a native-test stage carries a receipt'
echo 'objc-source-receipt: the shipping stage carries a receipt of exactly its prepared source'
