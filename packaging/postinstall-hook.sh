#!/bin/sh
# platform: host-agnostic
_icon="$ROOT/Library/Application Support/Mavergreen/recaulk-updater.app/Contents/Resources/recaulk-updater.icns"
_coretypes="$ROOT/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"
if [ -f "$_icon" ]; then
  for _c in GenericFrameworkIcon.icns LibraryFolderIcon.icns KEXT.icns; do
    if [ -f "$_coretypes/$_c" ]; then
      cp "$_coretypes/$_c" "$_icon" 2>/dev/null || true
      break
    fi
  done
fi
# spec: README.md "The kernel back-fill kext" -- 10.9 rebuilds its kext caches on its own, later; this makes a consumer's
#       first load of a kext depending on RecaulkKPI immediate. Only on the boot volume, and a failure only delays that.
if [ -z "$ROOT" ]; then
  /usr/sbin/kextcache -system-caches || echo "recaulk: kextcache -system-caches failed; 10.9 rebuilds its caches on its own" >&2
fi
