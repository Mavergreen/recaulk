#!/bin/sh
# platform: host-agnostic -- links an x86_64 program against librecaulk.a with clang22; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "Declarations" -- LSCopyApplicationURLsForBundleIdentifier (10.10), declared through
#       <CoreServices/CoreServices.h>: an application's URL for its bundle identifier, or NULL and a
#       kLSApplicationNotFoundErr error.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" tests/c/launchservices_bundle_urls.c \
    "$T/lib/librecaulk.a" -framework CoreFoundation -framework CoreServices -o "$(tbin program)"
  check_loads "$(tbin program)"
fi
runtime_half
"$(tbin program)"
