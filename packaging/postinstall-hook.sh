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
# spec: README.md "The kernel-fixes kext" -- RecaulkKernelFixes' kqueue_scan_restart replaces Wowfunhappy's
#       KQueueScanContinuePatch, so his kext and its LaunchDaemon go from any target volume. On the boot volume his
#       job is unloaded first and Recaulk's is loaded; a kernel his kext already patched stays patched until reboot,
#       and RecaulkKernelFixes reports that fix as applied by another kext. A failure here is logged, never fatal.
_wd="$ROOT/Library/LaunchDaemons/wowfunhappy.KQueueScanContinuePatch-loader.plist"
if [ -z "$ROOT" ] && [ -f "$_wd" ]; then
  # platform: guarded macOS-only call -- only when $ROOT is empty: the boot volume, where installer runs on 10.9
  /bin/launchctl unload "$_wd" 2>/dev/null || echo "recaulk: could not unload $_wd" >&2
fi
rm -f "$_wd" || echo "recaulk: could not remove $_wd" >&2
rm -rf "$ROOT/Library/Extensions/KQueueScanContinuePatch.kext" || echo "recaulk: could not remove KQueueScanContinuePatch.kext" >&2
# spec: README.md "The kernel-fixes kext" -- 10.9's kextd refuses an unsigned kext in /Library/Extensions unless its
#       bundle id is in OSKextSigExceptionList; list RecaulkKernelFixes at its installed version. kextd reads that list
#       once, so on the boot volume it is restarted (launchd starts it again) before the kext's job loads it.
_kl="$ROOT/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist"
_kv="$(awk '/<key>CFBundleVersion<\/key>/ { getline; gsub(/.*<string>|<\/string>.*/, ""); print; exit }' \
  "$ROOT/Library/Extensions/RecaulkKernelFixes.kext/Contents/Info.plist" 2>/dev/null || :)"
if [ -n "$_kv" ] && sh "$ROOT/usr/local/mavergreen/recaulk/libexec/recaulk/kext-exception.sh" add "$_kl" \
  dev.mavergreen.recaulk.kernelfixes "$_kv"; then
  if [ -z "$ROOT" ]; then
    # platform: guarded macOS-only call -- only when $ROOT is empty: the boot volume, where installer runs on 10.9
    /bin/launchctl stop com.apple.kextd 2>/dev/null || echo "recaulk: could not restart kextd; RecaulkKernelFixes loads at the next boot" >&2
  fi
else
  echo "recaulk: could not list RecaulkKernelFixes in $_kl; 10.9 loads it only with kext-dev-mode=1" >&2
fi
if [ -z "$ROOT" ]; then
  # spec: README.md "The kernel-fixes kext" -- on an upgrade the job and the kext already run; the kernel keeps the
  #       running kext (it cannot unload once applied), and the new one takes over at the next boot
  # platform: guarded macOS-only call -- only when $ROOT is empty: the boot volume, where installer runs on 10.9
  if /bin/launchctl list dev.mavergreen.recaulk.kernelfixes >/dev/null 2>&1; then
    echo "recaulk: RecaulkKernelFixes is already loaded; this version takes over at the next boot" >&2
  else
    # platform: guarded macOS-only call -- only when $ROOT is empty: the boot volume, where installer runs on 10.9
    /bin/launchctl load /Library/LaunchDaemons/dev.mavergreen.recaulk.kernelfixes.plist \
      || echo "recaulk: could not load RecaulkKernelFixes' LaunchDaemon; it loads at the next boot" >&2
  fi
fi
# spec: README.md "The kernel back-fill kext" -- 10.9 rebuilds its kext caches on its own, later; this makes a consumer's
#       first load of a kext depending on RecaulkKPI immediate. Only on the boot volume, and a failure only delays that.
if [ -z "$ROOT" ]; then
  /usr/sbin/kextcache -system-caches || echo "recaulk: kextcache -system-caches failed; 10.9 rebuilds its caches on its own" >&2
fi
