#!/bin/sh
# platform: host-agnostic -- links AppKit consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C methods" -- the accessibility bridge: an app calls recaulk_accessibility_bridge once per
#       class that implements only 10.10's NSAccessibility getters, and 10.9's attribute API then answers from them.
#       Uncalled it adds nothing; with Recaulk's NSView and NSCell setter groups linked too, neither loops into the other.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
A="$T/lib/librecaulk-objc.a"
SETTERS="-Wl,-u,___recaulk_objc_activate_view_accessibility -Wl,-u,___recaulk_objc_activate_cell_accessibility"
if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  [ -f "$T/include/recaulk/recaulk/accessibility.h" ] || { echo "FAIL: the stage has no include/recaulk/recaulk/accessibility.h"; exit 1; }
  # spec: Drydock's own-absent bridge (drydock, 2026-11-25) -- an IMP's getter and super sends stay in the IMP, so
  #       accessibility-bridge.o's code is the root and its ten IMPs, each helper inlined; and drydock's executor has
  #       no SSE, so the root holds no vector instruction
  fns="$("$NM" -m "$A" 2>/dev/null | awk '/(^|[(\/])accessibility-bridge\.o\)?:$/ { on = 1; next } /^$/ || /\.o\)?:$/ { on = 0 }
    on && /\(__TEXT,__text\)/ { print $NF }' | LC_ALL=C sort | tr '\n' ' ')"
  want="___recaulk_objc_axb_action_description ___recaulk_objc_axb_action_names ___recaulk_objc_axb_attribute_names \
___recaulk_objc_axb_attribute_value ___recaulk_objc_axb_is_attribute_settable ___recaulk_objc_axb_is_ignored \
___recaulk_objc_axb_parameterized_names ___recaulk_objc_axb_parameterized_value ___recaulk_objc_axb_perform_action \
___recaulk_objc_axb_set_value _recaulk_accessibility_bridge "
  [ "$fns" = "$want" ] || { echo "FAIL: accessibility-bridge.o's functions are not the root and its IMPs alone: $fns"; exit 1; }
  "$OTOOL" -tV -p _recaulk_accessibility_bridge "$A" 2>/dev/null \
    | awk '/^_recaulk_accessibility_bridge:/ { on = 1; next } on && /^_/ { exit } on' | grep -q '%xmm' \
    && { echo "FAIL: the bridge's root uses SSE, which drydock's executor cannot measure"; exit 1; }
  # spec: Drydock's source map (drydock, 2026-11-26) -- a send the line table puts at no source line is one call site
  #       shared by several sends (tail merging, sinking), which no receipt send can close, so every objc_msgSend call
  #       or jump in accessibility-bridge.o has its own source line
  SYMBOLIZER=$(dirname "$CC")/llvm-symbolizer; OBJDUMP=$(dirname "$CC")/llvm-objdump
  if [ -x "$SYMBOLIZER" ] && [ -x "$OBJDUMP" ]; then
    M="$(dirname "$(tbin x)")/bridge-members"; rm -rf "$M"; mkdir -p "$M"
    (cd "$M" && "$(dirname "$CC")/llvm-ar" x "$A" accessibility-bridge.o) || exit 1
    "$OBJDUMP" -d -r --no-show-raw-insn "$M/accessibility-bridge.o" | awk '
      /^ *[0-9a-f]+:/ { a = $1; sub(":", "", a); call = ($0 ~ /(callq|jmpq)[ \t]+\*/) }
      /^ *[0-9a-f]+:/ && /(callq|jmpq)[ \t]+\*%/ { print "0x" a }
      /X86_64_RELOC/ && /_objc_msgSend/ && call { print "0x" a }' | sort -u > "$M/sites"
    [ -s "$M/sites" ] || { echo "FAIL: found no send site in accessibility-bridge.o"; exit 1; }
    "$SYMBOLIZER" --obj="$M/accessibility-bridge.o" < "$M/sites" | awk 'NR % 3 == 2' > "$M/lines"
    paste "$M/sites" "$M/lines" | awk '$2 ~ /:0(:|$)/' > "$M/line0"
    [ ! -s "$M/line0" ] || { echo "FAIL: accessibility-bridge.o has $(wc -l < "$M/line0" | tr -d ' ') send sites at no source line, e.g. $(head -1 "$M/line0")"; exit 1; }
  else
    # platform: the Linux clang22 archive may carry no llvm-symbolizer (build/fetch-clang22.sh); the Mac run checks it
    echo "objc-accessibility-bridge: no llvm-symbolizer beside $CC; the send-line check runs where there is one"
  fi
  # spec: README.md "Objective-C methods" -- the declaration's own-absent group is the bridge build/objc-provider-manifest.sh
  #       lists, each member with its super_fallbacks record and 10.9's encoding: a record dropped, or an encoding
  #       clang22 doesn't compile for the member, is refused
  D="$(dirname "$(tbin x)")"
  python3 -I - src/objc/providers.json "$D" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
b = [g for g in d["providers"] if g["provider_id"] == "recaulk.accessibility.bridge.v1"][0]
b["super_fallbacks"].pop()
json.dump(d, open(sys.argv[2] + "/bridge-no-fallback.json", "w"), indent=2)
b["super_fallbacks"] = [{"implementation_symbol": m["implementation_symbol"], "selector": m["selector"]} for m in b["methods"]]
b["methods"][0]["encoding"] = "@24@0:8@16"
json.dump(d, open(sys.argv[2] + "/bridge-bad-encoding.json", "w"), indent=2)
PY
  for m in no-fallback bad-encoding; do
    if CC="$CC" TARGET_FLAGS="$TARGET_FLAGS" SDK="$SDK" sh build/objc-provider-manifest.sh header "$D/bridge-$m.json" \
      "$D/bridge-$m.h" > "$D/bridge-$m.log" 2>&1; then
      echo "FAIL: the manifest generator accepted a bridge declaration with $m"; exit 1
    fi
  done
  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -isystem "$T/include/recaulk" -c tests/c/objc_accessibility_bridge.m \
    -o "$(tbin bridge.o)"
  "$CC" $FLAGS "$(tbin bridge.o)" "$A" -framework AppKit -o "$(tbin bridge)"
  "$CC" $FLAGS "$(tbin bridge.o)" "$A" $SETTERS -framework AppKit -o "$(tbin bridge-with-setters)"
  check_loads "$(tbin bridge)" "$(tbin bridge-with-setters)"
fi
runtime_half
"$(tbin bridge)" unbridged
"$(tbin bridge)" bridged
"$(tbin bridge-with-setters)" bridged
"$(tbin bridge-with-setters)" bridged-with-setters
echo "objc-accessibility-bridge OK"
