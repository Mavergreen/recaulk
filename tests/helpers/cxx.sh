#!/bin/sh
# platform: macOS-only -- probes Apple clang++ against the pinned SDKs
# platform: C++11, what 10.9's Apple clang 6 offers; a clang that knows -fchar8_t (Apple clang 10+) adds
#           the char8_t checks in that same mode
CXX_STD="-std=c++11"
printf 'char8_t c;\n' | /usr/bin/clang++ -std=c++11 -fchar8_t -x c++ -fsyntax-only - 2>/dev/null && CXX_STD="$CXX_STD -fchar8_t"
# platform: 10.9's clang carries libc++'s headers; a current Apple clang looks for them in the SDK, and the
#           10.9 SDK has none, so it gets the pinned 11.3 SDK's (headers only: it still links 10.9's).
if ! printf '#include <cstdio>\n' | /usr/bin/clang++ $FLAGS -arch x86_64 $CXX_STD -x c++ -fsyntax-only - 2>/dev/null; then
  SDK113="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)"
  [ -d "$SDK113/usr/include/c++/v1" ] || { echo "FAIL: no libc++ headers from the compiler or the 11.3 SDK ($SDK113)"; exit 1; }
  CXX_STD="$CXX_STD -nostdinc++ -isystem $SDK113/usr/include/c++/v1"
fi
