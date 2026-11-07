#!/bin/sh
# platform: host-agnostic
# spec: INGREDIENTS.md "clang22" -- clang-22 repackages on every Recaulk release, so a clang22 pin that cut a Recaulk
#       release would make the two repos release each other forever; a clang22 bump reaches Recaulk's bytes at its
#       next release for another reason
set -eu
cd "$(dirname "$0")/.."
fail=0
bad() { echo "FAIL: $*"; fail=1; }

declared="$(awk '/^## / { on = ($0 == "## Declared state"); next } on && /^- [^:]+:/ { sub(/^- [^:]+: */, ""); print }' INGREDIENTS.md)"
[ -n "$declared" ] || bad "INGREDIENTS.md declares no state, so this test cannot tell what releases Recaulk"
printf '%s\n' "$declared" | grep -q '^UPSTREAM_VERSION$' || bad "the declared state lost its upstream entry, so this test is not reading it: $declared"
if printf '%s\n' "$declared" | grep -q 'clang22'; then
  bad "the declared state names a clang22 pin ($(printf '%s\n' "$declared" | grep clang22 | tr '\n' ' ')): a clang22 bump would cut a Recaulk release, which clang-22 repackages on, forever"
fi

paths="$(sed -n '/^ *paths:/,/^[^ ]/p' .github/workflows/repackage-on-ingredient-bump.yml | sed -n 's/^ *- *//p' | tr -d "\"'")"
printf '%s\n' "$paths" | grep -q 'components/drydock/version' || bad "repackage-on-ingredient-bump.yml's paths lost drydock, so this test is not reading them: $paths"
set -f
for p in $paths; do
  case "$p" in
    *clang22*|components/\*|components/\*\*|'components/*/version'|'components/**') bad "repackage-on-ingredient-bump.yml triggers on $p, which a clang22 bump moves: Recaulk and clang-22 would repackage each other forever" ;;
  esac
done
set +f

grep -qx -- '- self-upstream-exclude:components/clang22/linux-sha256: [^ ].*' INGREDIENTS.md \
  || bad "INGREDIENTS.md does not exclude components/clang22/linux-sha256 from own code, so the pins bot's digest commit would date a new Recaulk version"

[ "$fail" = 0 ] && echo "clang22-not-a-release-input OK"
exit $fail
