#!/bin/sh
# platform: host-agnostic -- links an x86_64 program against librecaulk.a with clang22; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "AppKit data" -- librecaulk.a defines NSPasteboardTypeFileURL (10.13) as "public.file-url",
#       needing CoreFoundation only, never AppKit.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Werror tests/c/pasteboard_file_url.c "$T/lib/librecaulk.a" \
    -framework CoreFoundation -framework CoreServices -o "$(tbin program)"
  if "$OTOOL" -L "$(tbin program)" | grep -q '/AppKit\.framework/'; then
    echo "FAIL: a program using librecaulk.a's NSPasteboardTypeFileURL loads AppKit"; exit 1
  fi
  check_loads "$(tbin program)"
fi
runtime_half
"$(tbin program)"
