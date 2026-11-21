#!/bin/sh
# platform: host-agnostic -- reads src/objc
# spec: README.md "How to use" (librecaulk-objc.a) -- Drydock's strict Objective-C guard reads each selector librecaulk-objc.a makes
#       from a literal at the call that makes it, and fails a program in which it cannot (codex-cli run 44722242164,
#       "computed-selector-producer", from a helper that registered a name its caller passed). So every
#       sel_registerName, sel_getUid or NSSelectorFromString in src/objc takes a string literal or a
#       RECAULK_*_SELECTOR macro, which build/objc-provider-manifest.sh defines as one.
set -eu
cd "$(dirname "$0")/.."
bad="$(grep -rnE 'sel_registerName|sel_getUid|NSSelectorFromString' src/objc \
  | grep -vE '(sel_registerName|sel_getUid|NSSelectorFromString)\((\"|RECAULK_[A-Z0-9_]+_SELECTOR\))' || :)"
[ -z "$bad" ] || { printf 'FAIL: a selector made from something other than a literal:\n%s\n' "$bad"; exit 1; }
grep -q "printf '#define RECAULK_%s_SELECTOR \"%s\"" build/objc-provider-manifest.sh \
  || { echo "FAIL: build/objc-provider-manifest.sh no longer defines RECAULK_*_SELECTOR as a string literal"; exit 1; }
echo "objc-literal-selectors OK"
