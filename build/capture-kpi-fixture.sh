#!/bin/sh
# platform: macOS-only -- 10.9 only: reads the running system's KPI symbol-set kexts (PlistBuddy); run once by hand, then commit the result
# spec: tests/fixtures/kpi-10.9/PROVENANCE.md -- the public KPI export lists RecaulkKPI.kext may import from,
#       one file per library bundle id, one symbol per line, sorted
set -eu
cd "$(dirname "$0")/.."
. build/lib.sh
recaulk_tools
[ "$(uname -r | cut -d. -f1)" = 13 ] || { echo "capture-kpi-fixture: run this on 10.9 (Darwin 13), not $(uname -sr)" >&2; exit 1; }
P=/System/Library/Extensions/System.kext/PlugIns
out=tests/fixtures/kpi-10.9
mkdir -p "$out"
for k in BSDKernel Libkern Mach Unsupported; do
  id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$P/$k.kext/Info.plist")"
  # platform: a KPI kext is a symbol set: every name it exports appears in its symbol table
  "$NM" -j "$P/$k.kext/$k" | LC_ALL=C sort -u > "$out/$id.txt"
done
