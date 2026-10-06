#!/bin/sh
# platform: macOS-only -- pkgbuild and productbuild assemble the pkg
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/lib.sh"

BUILD="${BUILD:-$(recaulk_build_dir)}"
OUT="${OUT:-$BUILD/out}"
: "${UPD_APP:?package-pkg: UPD_APP (built updater .app) required}"
: "${VERSION:?package-pkg: VERSION (full version) required}"
SCRIPTS="$SHIPYARD_SCRIPTS"
STAGE="$BUILD/stage"
ID="dev.mavergreen.recaulk"
TREE="$STAGE/usr/local/mavergreen/recaulk"
mkdir -p "$OUT"

sh "$SCRIPTS/assert_binary_compatible.sh" "$TREE/lib/libRecaulkSystem.dylib" >&2

SCR="$OUT/pkg-scripts"; rm -rf "$SCR"
sh "$SCRIPTS/stage_product.sh" --stage "$STAGE" --product recaulk \
  --name "Recaulk for Mavericks" --version "$VERSION" --updater-app "$UPD_APP" \
  --postinstall-hook "$MAVERICKS_ROOT/packaging/postinstall-hook.sh" --scripts-out "$SCR" >&2

mkdir -p "$OUT/component"
comp="$OUT/component/recaulk-component.pkg"
pkgbuild --root "$STAGE" --identifier "$ID" --version "$VERSION" --scripts "$SCR" \
  --install-location / "$comp" >&2

final="$OUT/recaulk-${VERSION}.pkg"
sh "$SCRIPTS/set_install_floor.sh" --identifier "$ID" --title "Recaulk for Mavericks ${VERSION}" \
  --component "$comp" --out "$final" --host-arch x86_64 --require-scripts >&2

printf '%s\n' "$final"
