#!/bin/sh
# platform: host-agnostic -- builds an x86_64 program with clang22; runs it on 10.9 (RECAULK_TEST_PHASE)
# spec: README.md "SDK declaration metadata" -- foundation-processinfo-version-v1 declares NSProcessInfo's
#       operatingSystemVersion and isOperatingSystemAtLeastVersion: plainly, with no back-fill, because 10.9.5's
#       Foundation already implements them; this holds it to that.
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -fno-objc-arc -Wall -Werror tests/c/foundation_os_version.m -framework Foundation \
    -o "$(tbin program)"
  check_loads "$(tbin program)"
fi
runtime_half
"$(tbin program)"
