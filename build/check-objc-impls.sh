#!/bin/sh
# platform: host-agnostic
#   usage: check-objc-impls.sh STAGE_PREFIX
#          checks that every implementation_symbol STAGE_PREFIX/share/recaulk/objc-providers.json declares is a
#          defined external symbol of STAGE_PREFIX/lib/librecaulk-objc.a (N_EXT; hidden visibility is fine,
#          `static` is not). shipyard's analyzer resolves provider implementations only among those.
set -eu
SELF=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
. "$SELF/lib.sh"
[ "$#" = 1 ] || { sed -n 3p "$0" >&2; exit 2; }
decl=$1/share/recaulk/objc-providers.json archive=$1/lib/librecaulk-objc.a
[ -f "$decl" ] && [ -f "$archive" ] || { echo "check-objc-impls: $1 has no objc-providers.json or librecaulk-objc.a" >&2; exit 1; }
recaulk_tools
symbols=$(sed -n 's/^[[:space:]]*"implementation_symbol"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$decl")
[ -n "$symbols" ] || { echo "check-objc-impls: $decl declares no implementation_symbol" >&2; exit 1; }
defined=$("$NM" -g --defined-only "$archive" 2>/dev/null | awk 'NF >= 3 { print $NF }')
bad=0
for s in $symbols; do
  printf '%s\n' "$defined" | grep -Fx "_$s" > /dev/null && continue
  echo "check-objc-impls: $s is not a defined external symbol of $archive" >&2
  bad=1
done
exit "$bad"
