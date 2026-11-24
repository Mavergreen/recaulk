#!/bin/sh
# platform: host-agnostic
# spec: README.md "The kernel-fixes kext" -- shipyard's uninstall runs this before removing Recaulk (MAVERGREEN_ROOT is
#       the volume): RecaulkKernelFixes leaves OSKextSigExceptionList, so Apple's exclude list is as it was. A failure
#       is reported and never stops the uninstall.
set -u
V="${MAVERGREEN_ROOT:-/}"; V="${V%/}"
sh "$V/usr/local/mavergreen/recaulk/libexec/recaulk/kext-exception.sh" remove \
  "$V/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist" dev.mavergreen.recaulk.kernelfixes \
  || echo "recaulk: could not remove RecaulkKernelFixes from OSKextSigExceptionList" >&2
exit 0
