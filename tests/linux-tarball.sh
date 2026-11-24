#!/bin/sh
# platform: Linux-only -- GNU tar packs the tarball, and the static Linux recaulk-materialize it carries runs only here
# spec: README.md "Materializing an SDK view" -- recaulk-<version>-linux-x86_64.tar.gz holds opt/mavergreen/recaulk/,
#       the .pkg's usr/local/mavergreen/recaulk/ tree (lib, include, share) with a static Linux bin/recaulk-materialize
#       that finds ../share/sdk-metadata; owned by 0:0, reproducible
set -eu
cd "$(dirname "$0")/.."
. build/lib.sh
B="$(recaulk_build_dir)"
[ -f "$B/stage/usr/local/mavergreen/recaulk/lib/librecaulk.a" ] || { echo "not built: run sh build/build-lib.sh first"; exit 77; }
d="$(mktemp -d "${TMPDIR:-/tmp}/linux-tarball.XXXXXX")"
trap 'rm -rf "$d"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
export SOURCE_DATE_EPOCH=1764000000
t1="$(VERSION=20261124.9 OUT="$d/a" sh build/package-linux-tarball.sh)"
t2="$(VERSION=20261124.9 OUT="$d/b" sh build/package-linux-tarball.sh)"
[ "$(basename "$t1")" = recaulk-20261124.9-linux-x86_64.tar.gz ] || bad "the tarball is named $(basename "$t1")"
cmp -s "$t1" "$t2" || bad "two packings of one tree differ"
tar -tzvf "$t1" > "$d/list"
P=opt/mavergreen/recaulk
for f in bin/recaulk-materialize share/sdk-metadata/recipes.json share/sdk-metadata/profiles.json lib/librecaulk.a \
         lib/librecaulk-objc.a include/recaulk/MacportsLegacySupport.h share/recaulk/notices.tsv; do
  grep -q " $P/$f\$" "$d/list" || bad "the tarball lacks $P/$f"
done
awk '{ print $NF }' "$d/list" | grep -v "^$P/" | grep -v '^opt/$\|^opt/mavergreen/$' && bad "the tarball holds something outside $P"
awk '{ print $2 }' "$d/list" | grep -v '^0/0$' && bad "an entry is not owned by 0/0"
grep " $P/bin/recaulk-materialize\$" "$d/list" | grep -q '^-rwxr-xr-x' || bad "bin/recaulk-materialize is not 0755"
mkdir "$d/x" && tar -xzf "$t1" -C "$d/x"
RM="$d/x/$P/bin/recaulk-materialize"
file "$RM" | grep -q 'statically linked' || bad "recaulk-materialize is not static: $(file "$RM")"
[ "$("$RM" --version)" = "recaulk-materialize 20261124.9" ] || bad "it says $("$RM" --version)"
"$RM" --print-stamp --profile swift-foundation >/dev/null || bad "the unpacked binary does not find ../share/sdk-metadata"
[ "$fail" = 0 ] && echo "linux-tarball OK"
exit "$fail"
