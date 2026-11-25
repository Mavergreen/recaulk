#!/bin/sh
# platform: host-agnostic -- links an AppKit consumer of the stand-in stub with clang22; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Stand-in classes" -- lib/stand-in/libRecaulkAppKit.dylib holds RecaulkAccessibilityElement, exported
#       as NSAccessibilityElement's class and metaclass; lib/stub/libRecaulkAppKit.dylib has the same install name and
#       exports no class. An app links the stub weakly and binds the class flat and weak, so 10.10 and later give it
#       AppKit's class and 10.9 Recaulk's; without the stand-in it still loads, with the subclass missing.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
REAL="$T/lib/stand-in/libRecaulkAppKit.dylib"
STUB="$T/lib/stub/libRecaulkAppKit.dylib"
CLASS='_OBJC_CLASS_$_NSAccessibilityElement'
META='_OBJC_METACLASS_$_NSAccessibilityElement'
fail() { echo "FAIL: $*"; exit 1; }
if compiling; then
  for f in "$REAL" "$STUB"; do [ -f "$f" ] || fail "the stage has no ${f#"$T"/}"; done
  for f in "$REAL" "$STUB"; do
    [ "$("$OTOOL" -D "$f" | sed -n 2p)" = @rpath/libRecaulkAppKit.dylib ] || fail "${f#"$T"/}'s install name is not @rpath/libRecaulkAppKit.dylib"
  done
  real="$("$NM" -gU "$REAL" | awk '{ print $NF }')"
  for s in "$CLASS" "$META"; do
    printf '%s\n' "$real" | grep -qxF "$s" || fail "the stand-in does not export $s"
  done
  printf '%s\n' "$real" | grep -q 'RecaulkAccessibilityElement' && fail "the stand-in exports its class under its own name too"
  "$NM" -gU "$STUB" | grep -q 'OBJC_CLASS_\$\|OBJC_METACLASS_\$' && fail "the stub exports a class, which an app would bind two-level"
  # spec: Drydock's provided-class plan -- it names each method by its implementation's local symbol, so the shipped
  #       stand-in keeps them (no strip -x; tests/package-pkg.sh holds the packaged copy byte-identical to this one)
  for m in '+[RecaulkAccessibilityElement accessibilityElementWithRole:frame:label:parent:]' \
           '-[RecaulkAccessibilityElement accessibilityRole]' '-[RecaulkAccessibilityElement accessibilityAttributeValue:]'; do
    "$NM" -m "$REAL" | grep -qF "non-external $m" || fail "the stand-in lacks the local symbol $m"
  done
  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -c tests/c/objc_accessibility_standin.m -o "$(tbin standin.o)"
  for v in with without; do
    mkdir -p "$(tbin "$v")"
    # spec: README.md "Stand-in classes" -- AppKit first, so a flat lookup finds AppKit's class before the stand-in's
    "$CC" $FLAGS "$(tbin standin.o)" -framework AppKit -Wl,-weak_library,"$STUB" \
      -Wl,-U,"$CLASS" -Wl,-U,"$META" -Wl,-rpath,@loader_path/. -o "$(tbin "$v")/standin"
  done
  cp "$REAL" "$(tbin with)/libRecaulkAppKit.dylib"
  rm -f "$(tbin without)/libRecaulkAppKit.dylib"
  # platform: 10.9's dyld expands an rpath's @loader_path only before a slash (dyld-239 ImageLoader::getRPaths), hence
  #           "@loader_path/." above; check_loads refuses @rpath, and this program loads the stand-in from beside
  #           itself, weakly, by design
  "$OTOOL" -l "$(tbin with)/standin" | grep -A2 LC_LOAD_WEAK_DYLIB | grep -q 'name @rpath/libRecaulkAppKit.dylib' \
    || fail "the app does not load the stand-in weakly by @rpath"
fi
runtime_half
"$(tbin with)/standin" with
"$(tbin without)/standin" without
echo "objc-accessibility-standin OK"
