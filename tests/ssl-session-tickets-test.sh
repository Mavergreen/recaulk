#!/bin/sh
# platform: host-agnostic -- builds the staged static archive and dylib's x86_64 programs; runs them on 10.9 (RECAULK_TEST_PHASE)
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
if compiling; then
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" \
    tests/c/ssl_session_tickets.c "$T/lib/librecaulk.a" -framework Security -framework CoreFoundation -o "$(tbin static)"
  "$CC" $FLAGS -arch x86_64 -Wall -Werror -isystem "$T/include/recaulk" \
    tests/c/ssl_session_tickets.c -L"$T/lib" -lRecaulkSystem -framework Security -framework CoreFoundation -o "$(tbin dylib)"
  check_loads "$(tbin static)" "$(tbin dylib)"
fi
runtime_half
"$(tbin static)"
DYLD_LIBRARY_PATH="$T/lib" "$(tbin dylib)"
