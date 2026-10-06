#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
git --version >/dev/null 2>&1 || { echo "no git -- skipping" >&2; exit 77; }
ROOT="$(pwd)"
D="$(mktemp -d "${TMPDIR:-/tmp}/fetch-macports.XXXXXX")"
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

mkdir "$D/fixture"
(
  cd "$D/fixture"
  git init -q .
  mkdir include src
  printf 'all:\n' > Makefile
  printf '/* header */\n' > include/MacportsLegacySupport.h
  printf 'int x;\n' > src/x.c
  git add Makefile include src
  git -c user.name=t -c user.email=t@example.com commit -q -m fixture
)
digest="$(git -C "$D/fixture" rev-parse HEAD)"
mkdir -p "$D/codeload/macports/macports-legacy-support/tar.gz"
git -C "$D/fixture" archive --format=tar --prefix="macports-legacy-support-$digest/" HEAD | gzip -n \
  > "$D/codeload/macports/macports-legacy-support/tar.gz/$digest"
sha="$(shasum -a 256 "$D/codeload/macports/macports-legacy-support/tar.gz/$digest" | cut -d' ' -f1)"

copy() {
  mkdir -p "$D/$1/components/macports-legacy-support"
  cp -R "$ROOT/build" "$D/$1/build"
  sed -e "s/^DIGEST=.*/DIGEST=$digest/" -e "s/^TARBALL_SHA256=.*/TARBALL_SHA256=$2/" \
    "$ROOT/components/macports-legacy-support/version" > "$D/$1/components/macports-legacy-support/version"
}
copy good "$sha"
copy bad 0000000000000000000000000000000000000000000000000000000000000000

run() {
  (
    unset MAVERICKS_ROOT
    MAVERICKS_CODELOAD="file://$D/codeload" MAVERICKS_SOURCE_CACHE="$D/$2"
    export MAVERICKS_CODELOAD MAVERICKS_SOURCE_CACHE
    sh "$D/$1/build/fetch-macports.sh" "$3"
  )
}

want="macports-legacy-support-$(. build/lib.sh; macports_version)"
out="$(run good cache "$D/dest" 2>/dev/null)" || bad "fetch failed"
case "$out" in */"$want") ;; *) bad "printed '$out', want a path ending $want" ;; esac
for f in Makefile include/MacportsLegacySupport.h src/x.c; do
  [ -f "$out/$f" ] || bad "$f missing from $out"
done

touch "$out/dropped"
run good cache "$D/dest" >/dev/null 2>&1 || bad "second fetch failed"
[ ! -e "$out/dropped" ] || bad "a second run did not re-extract"

touch "$out/kept"
err="$(run bad cache2 "$D/dest" 2>&1 >/dev/null)" && bad "a wrong TARBALL_SHA256 was accepted"
case "$err" in *pin-source-tarball.sh*) ;; *) bad "stderr does not name pin-source-tarball.sh: $err" ;; esac
[ -e "$out/kept" ] || bad "a failed fetch changed the extracted directory"

copy nodigest "$sha"
pin="$D/nodigest/components/macports-legacy-support/version"
sed '/^DIGEST=/d' "$pin" > "$pin.new" && mv "$pin.new" "$pin"
rc=0
err="$(run nodigest cache3 "$D/dest3" 2>&1 >/dev/null)" || rc=$?
[ "$rc" != 0 ] || bad "a pin missing DIGEST was accepted"
case "$err" in *DIGEST*) ;; *) bad "stderr does not name DIGEST: $err" ;; esac
case "$err" in *pin-source-tarball.sh*) bad "a missing key was reported as a verification failure" ;; esac

rc=0
err="$( (. build/lib.sh; macports_pin NOPE) 2>&1)" || rc=$?
[ "$rc" = 1 ] || bad "macports_pin NOPE exited $rc, want 1"
case "$err" in *NOPE*) ;; *) bad "macports_pin NOPE does not name NOPE: $err" ;; esac

[ "$fail" = 0 ] && echo "fetch-macports OK"
exit $fail
