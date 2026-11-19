#!/bin/sh
# platform: host-agnostic -- links AppKit consumers of librecaulk-objc.a with clang22; runs them on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Objective-C methods" -- -[NSWorkspace isVoiceOverEnabled] reads universal access's
#       voiceOverOnOffKey, behind the AppKit root ___recaulk_objc_activate; unrooted, NSWorkspace lacks it.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
A="$T/lib/librecaulk-objc.a"
if compiling; then
  [ -f "$A" ] || { echo "FAIL: the stage has no lib/librecaulk-objc.a"; exit 1; }
  "$CC" $FLAGS -fno-objc-arc -Wall -Werror -c tests/c/objc_workspace_voiceover.m -o "$(tbin voiceover.o)"
  # platform: the unrooted program calls the helper too, so it links; -u is what activates the provider
  "$CC" $FLAGS "$(tbin voiceover.o)" "$A" -framework AppKit -framework Carbon -o "$(tbin unrooted)"
  "$CC" $FLAGS "$(tbin voiceover.o)" "$A" -Wl,-u,___recaulk_objc_activate -framework AppKit -framework Carbon \
    -o "$(tbin rooted)"
  check_loads "$(tbin unrooted)" "$(tbin rooted)"
fi
runtime_half
"$(tbin unrooted)" unrooted
# platform: cfprefsd leaves the emptied throwaway domain's file behind (and, on 10.9, a temporary beside it)
trap 'rm -f "$HOME/Library/Preferences/dev.mavergreen.recaulk.test-voiceover.plist"*' EXIT
"$(tbin rooted)" rooted
echo "objc-workspace-voiceover OK"
