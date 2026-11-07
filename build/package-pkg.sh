#!/bin/sh
# platform: host-agnostic
#   usage: UPD_APP=<recaulk-updater.app> VERSION=<version> sh build/package-pkg.sh     prints OUT/recaulk-VERSION.pkg
#          (OUT defaults to the build tree's out/), made from the build tree's stage, and writes
#          OUT/build-info-release.txt: the pins and the build tools that build-tools.txt in the build tree and
#          beside the updater record
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/lib.sh"

BUILD="${BUILD:-$(recaulk_build_dir)}"
OUT="${OUT:-$BUILD/out}"
: "${UPD_APP:?package-pkg: UPD_APP (built updater .app) required}"
: "${VERSION:?package-pkg: VERSION (full version) required}"
[ -x "$UPD_APP/Contents/MacOS/recaulk-updater" ] \
  || { echo "package-pkg: $UPD_APP has no executable Contents/MacOS/recaulk-updater -- not a built updater; run build/build-updater.sh" >&2; exit 1; }
for f in "$BUILD/build-tools.txt" "$(dirname "$UPD_APP")/build-tools.txt"; do
  [ -s "$f" ] || { echo "package-pkg: no $f -- the build tools that built what ships must be recorded" >&2; exit 1; }
done
SCRIPTS="$SHIPYARD_SCRIPTS"
STAGE="$BUILD/stage"
ID="dev.mavergreen.recaulk"
TREE="$STAGE/usr/local/mavergreen/recaulk"
mkdir -p "$OUT"
rm -f "$OUT"/recaulk-*.pkg "$OUT"/build-info-*.txt
recaulk_tools

sh "$SCRIPTS/assert_binary_compatible.sh" "$TREE/lib/libRecaulkSystem.dylib" >&2

SCR="$OUT/pkg-scripts"; rm -rf "$SCR"
sh "$SCRIPTS/stage_product.sh" --stage "$STAGE" --product recaulk \
  --name "Recaulk for Mavericks" --version "$VERSION" --updater-app "$UPD_APP" \
  --postinstall-hook "$MAVERICKS_ROOT/packaging/postinstall-hook.sh" --scripts-out "$SCR" >&2

mkdir -p "$OUT/component"
comp="$OUT/component/recaulk-component.pkg"
sh "$SCRIPTS/build_component_pkg.sh" --root "$STAGE" --identifier "$ID" --version "$VERSION" --scripts "$SCR" \
  --install-location / --out "$comp" >&2

final="$OUT/recaulk-${VERSION}.pkg"
sh "$SCRIPTS/set_install_floor.sh" --identifier "$ID" --title "Recaulk for Mavericks ${VERSION}" \
  --component "$comp" --out "$final" --host-arch x86_64 --require-scripts >&2

pin() { tr -d ' \t\n' < "$MAVERICKS_ROOT/components/$1/version"; }
set -- variant=release arch=x86_64 prefix=/usr/local/mavergreen/recaulk pkg="recaulk-$VERSION.pkg" identifier="$ID" \
  clang22="$(pin clang22)" drydock="$(pin drydock)" macports-legacy-support="$(macports_pin REF)"
for f in "$BUILD/build-tools.txt" "$(dirname "$UPD_APP")/build-tools.txt"; do
  while IFS= read -r l; do set -- "$@" "$l"; done < "$f"
done
sh "$SCRIPTS/build-info.sh" "$OUT/build-info-release.txt" "$@"

printf '%s\n' "$final"
