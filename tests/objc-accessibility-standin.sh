#!/bin/sh
# platform: host-agnostic -- links AppKit consumers of Recaulk's shim with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Stand-in classes" -- lib/stand-in/libRecaulkAppKit.dylib holds RecaulkAccessibilityElement, a shim
#       with no compiled methods that an app subclasses two-level in place of 10.10's NSAccessibilityElement. Its one
#       constructor re-parents it onto AppKit's class where there is one, and otherwise (or when that fails, with one
#       NSLog line) adds the stand-in's methods. 10.9 has no NSAccessibilityElement, so a fixture dylib fakes one to run
#       the re-parent here, realizing the shim first (tests/c/objc_accessibility_standin_fixture.m says why); the real
#       re-parent of an unrealized shim, on 10.10 and later, is Drydock's modern gate to run.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
REAL="$T/lib/stand-in/libRecaulkAppKit.dylib"
fail() { echo "FAIL: $*"; exit 1; }
if compiling; then
  [ -f "$REAL" ] || fail "the stage has no ${REAL#"$T"/}"
  [ ! -e "$T/lib/stub" ] || fail "the stage still has lib/stub, which the shim needs no more"
  [ "$("$OTOOL" -D "$REAL" | sed -n 2p)" = @rpath/libRecaulkAppKit.dylib ] || fail "the shim's install name is not @rpath/libRecaulkAppKit.dylib"
  # spec: README.md "Stand-in classes" -- exported under its own two symbols only, no AppKit name anywhere
  [ "$("$NM" -gU "$REAL" | awk '/OBJC_/ { print $NF }' | sort | tr '\n' ' ')" = \
    '_OBJC_CLASS_$_RecaulkAccessibilityElement _OBJC_METACLASS_$_RecaulkAccessibilityElement ' ] \
    || fail "the shim's class exports are not exactly its own class and metaclass"
  "$NM" -a "$REAL" | grep -q NSAccessibilityElement && fail "the shim names NSAccessibilityElement in a symbol"
  "$NM" -m "$REAL" | grep -qF '[RecaulkAccessibilityElement ' && fail "the shim has a compiled method"
  # spec: build/build-standins.sh "Drydock names each stand-in method" -- the stand-in's IMPs keep theirs
  #       (no strip -x; tests/package-pkg.sh holds the packaged copy byte-identical to this one)
  for m in _sa_element _sa_role _sa_attributeValue; do
    "$NM" -m "$REAL" | grep -q "non-external $m\$" || fail "the shim lacks the local symbol $m"
  done
  "$NM" -m "$REAL" | grep -q 'weak external _class_setSuperclass (from libobjc)' \
    || fail "the shim does not import class_setSuperclass weakly"
  [ "$("$OTOOL" -l "$REAL" | grep -A4 'sectname __mod_init_func' | awk '$1 == "size" { print $2 }')" = 0x0000000000000008 ] \
    || fail "the shim does not have exactly one initializer"

  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -c tests/c/objc_accessibility_standin.m -o "$(tbin standin.o)"
  for v in standin reparent early conflict missing; do
    rm -rf "$(tbin "$v")"
    mkdir -p "$(tbin "$v")"
  done
  for f in FAKE:reparent EARLY:early CONFLICT:conflict; do
    # spec: tests/c/objc_accessibility_standin_fixture.m -- the conflict's category binds the shim, so it links it
    "$CC" -dynamiclib $FLAGS -fno-objc-arc -Wall -Werror -D"${f%%:*}" tests/c/objc_accessibility_standin_fixture.m \
      -framework Foundation $([ "${f%%:*}" = CONFLICT ] && echo "$REAL") \
      -install_name @executable_path/libFixture.dylib -o "$(tbin "${f#*:}")/libFixture.dylib"
  done
  for v in standin reparent early conflict missing; do
    fixture=
    [ -f "$(tbin "$v")/libFixture.dylib" ] && fixture="-Wl,-needed_library,$(tbin "$v")/libFixture.dylib"
    # spec: README.md "Stand-in classes" -- the subclass binds the shim two-level; the fixture first, so
    #       the early case's +load runs before the shim's constructor
    "$CC" $FLAGS "$(tbin standin.o)" $fixture "$REAL" -framework AppKit -Wl,-rpath,@loader_path/. -o "$(tbin "$v")/standin"
    [ "$v" = missing ] || cp "$REAL" "$(tbin "$v")/libRecaulkAppKit.dylib"
  done
  binds="$("$NM" -m "$(tbin standin)/standin")"
  for s in '_OBJC_CLASS_$_RecaulkAccessibilityElement' '_OBJC_METACLASS_$_RecaulkAccessibilityElement'; do
    printf '%s\n' "$binds" | grep -qF "(undefined) external $s (from libRecaulkAppKit)" \
      || fail "the app does not bind $s two-level and strongly to the shim"
  done
  # platform: 10.9's dyld expands an rpath's @loader_path only before a slash (dyld-239 ImageLoader::getRPaths), hence
  #           "@loader_path/." above; check_loads refuses @rpath, and these programs load the shim from beside them
fi
runtime_half
err=$(mktemp "${TMPDIR:-/tmp}/objc-accessibility-standin.XXXXXX")
trap 'rm -f "$err"' EXIT
# spec: README.md "Stand-in classes" -- RUN DIR MODE [LINE]: MODE passes, and stderr holds exactly
#       LINE's NSLog message (a prefix of it, for the install line's own consequence), or no Recaulk line without LINE
run() {
  "$(tbin "$1")/standin" "$2" 2> "$err" || { cat "$err"; fail "$1 $2 failed"; }
  got=$(sed -n 's/^.*\] \(Recaulk: \)/\1/p' "$err")
  case "${3:-}" in
    '') [ -z "$got" ] || fail "$1 printed '$got'" ;;
    *'; ') [ "$(printf '%s\n' "$got" | wc -l | tr -d ' ')" = 1 ] && [ "${got#"$3"}" != "$got" ] \
             || fail "$1 printed '$got', not one line beginning '$3'" ;;
    *) [ "$got" = "$3" ] || fail "$1 printed '$got', not '$3'" ;;
  esac
}
REPARENT='Recaulk: cannot re-parent RecaulkAccessibilityElement onto NSAccessibilityElement'
run standin standin
run reparent reparent
export RECAULK_DISABLE_REPARENT=1
run reparent fallback "$REPARENT (class_setSuperclass is unavailable); falling back to the built-in stand-in."
unset RECAULK_DISABLE_REPARENT
run early fallback \
  "$REPARENT (the shim was realized before this constructor, with NSObject's instance layout); falling back to the built-in stand-in."
run conflict conflict 'Recaulk: cannot install the stand-in methods on RecaulkAccessibilityElement; '
# spec: README.md "Stand-in classes" -- without the shim, dyld refuses the launch
{ "$(tbin missing)/standin" standin 2> "$err"; } 2>/dev/null && fail "the app launched without the shim"
grep -q 'libRecaulkAppKit.dylib' "$err" || { cat "$err"; fail "dyld's refusal does not name the shim"; }
echo "objc-accessibility-standin OK"
