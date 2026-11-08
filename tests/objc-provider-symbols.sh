#!/bin/sh
# platform: host-agnostic
# spec: build/check-objc-impls.sh -- every implementation_symbol objc-providers.json declares is a DEFINED EXTERNAL
#       symbol of librecaulk-objc.a (N_EXT, hidden visibility allowed). shipyard's analyzer resolves a provider's
#       implementation only among those, so a rename, a `static` or an -fvisibility change must fail here, not there.
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
. "$ROOT/build/msc.sh"
fail() { echo "FAIL: $*"; exit 1; }
D=$(mktemp -d "${TMPDIR:-/tmp}/objc-provider-symbols.XXXXXX")
D=$(cd "$D" && pwd -P)
trap 'rm -rf "$D"' EXIT
[ -f "$ROOT/build/check-objc-impls.sh" ] || fail 'build/check-objc-impls.sh is not implemented'
sh "$ROOT/build/build-objc.sh" "$D/stage" "$D/work" > "$D/build.log" 2>&1 || { tail -20 "$D/build.log"; fail 'companion build'; }
sh "$ROOT/build/check-objc-impls.sh" "$D/stage" > "$D/out" 2>&1 || { cat "$D/out"; fail 'the shipped stage fails its own check'; }
echo 'objc-provider-symbols: every declared implementation_symbol is a defined external of the archive'

# A manifest that names a symbol the archive lacks.
cp -R "$D/stage" "$D/renamed"
sed 's/"__recaulk_objc_workspace_open_urls"/"__recaulk_objc_workspace_open_urls_renamed"/' \
  "$D/stage/share/recaulk/objc-providers.json" > "$D/renamed/share/recaulk/objc-providers.json"
! sh "$ROOT/build/check-objc-impls.sh" "$D/renamed" > "$D/out" 2>&1 || fail 'a renamed implementation_symbol passed'
grep -F '__recaulk_objc_workspace_open_urls_renamed' "$D/out" > /dev/null || fail "the refusal does not name the symbol: $(cat "$D/out")"

# An archive whose implementation is file-local (static): defined, but not external.
. "$ROOT/build/lib.sh"
recaulk_tools
printf 'static void __recaulk_objc_workspace_open_urls(void) {}\nvoid *keep(void) { return (void *)__recaulk_objc_workspace_open_urls; }\n' > "$D/static.c"
"$CC" --no-default-config --target=x86_64-apple-macos10.9 -c "$D/static.c" -o "$D/static.o"
cp -R "$D/stage" "$D/static"
rm -f "$D/static/lib/librecaulk-objc.a"
recaulk_archive "$D/static/lib/librecaulk-objc.a" "$D/static.o"
! sh "$ROOT/build/check-objc-impls.sh" "$D/static" > "$D/out" 2>&1 || fail 'a static (file-local) implementation passed'
grep -F 'defined external' "$D/out" > /dev/null || fail "the refusal does not say why: $(cat "$D/out")"
echo 'objc-provider-symbols: a renamed or file-local implementation is refused'
