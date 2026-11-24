#!/bin/sh
# platform: host-agnostic
# usage: sh tests/fixtures/materialize/make-sdk.sh DIR   -- makes DIR/MacOSX10.9.sdk, a stand-in SDK with the
#        fixture headers where the 10.9 SDK has them, its Versions/Current and Headers links included
set -eu
F="$(cd "$(dirname "$0")" && pwd)"
s="$1/MacOSX10.9.sdk"
fw="$s/System/Library/Frameworks/Foundation.framework"
mkdir -p "$fw/Versions/C/Headers" "$s/usr/include"
cp "$F/NSArray.h" "$fw/Versions/C/Headers/NSArray.h"
cp "$F/stdio.h" "$s/usr/include/stdio.h"
cp "$F/SDKSettings.plist" "$s/SDKSettings.plist"
ln -s C "$fw/Versions/Current"
ln -s Versions/Current/Headers "$fw/Headers"
