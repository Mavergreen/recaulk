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

# spec: README.md "Materializing an SDK view" -- built here, where the release's VERSION is known, since its stamp
#       records it; beside ../share/sdk-metadata, which it reads
mkdir -p "$TREE/bin"
RECAULK_VERSION="$VERSION" sh "$MAVERICKS_ROOT/build/build-materialize.sh" mac "$TREE/bin/recaulk-materialize" >&2
chmod 755 "$TREE/bin/recaulk-materialize"
# spec: tests/package-pkg.sh -- consumers read share/ as themselves: drydock-objc receipt (via objc-source-inventory.sh) writes the
#       receipt owner-only, and a mode in the staged tree is what the pkg installs, so every file there is made 0644
find "$TREE/share" -type d -exec chmod 755 {} +
find "$TREE/share" -type f -exec chmod 644 {} +
sh "$SCRIPTS/assert_binary_compatible.sh" "$TREE/lib/libRecaulkSystem.dylib" >&2
# spec: README.md "Stand-in classes" -- the stand-in loads on 10.9 too, and the stub is what apps link
sh "$SCRIPTS/assert_binary_compatible.sh" "$TREE/lib/stand-in/libRecaulkAppKit.dylib" >&2
sh "$SCRIPTS/assert_binary_compatible.sh" "$TREE/lib/stub/libRecaulkAppKit.dylib" >&2
# spec: INGREDIENTS.md "Conformance deviations", arm64 -- recaulk-materialize is universal wherever the compiler
#       targets arm64 (tests/package-pkg.sh demands that slice then); the guard checks each slice it carries
MAVERICKS_ALLOW_ARCHS="$("$LIPO" -archs "$TREE/bin/recaulk-materialize")" \
  sh "$SCRIPTS/assert_binary_compatible.sh" "$TREE/bin/recaulk-materialize" >&2

# spec: README.md "The kernel back-fill kext" -- built here, where the release's VERSION is known, since its
#       CFBundleVersion is the release; staged where 10.9 loads third-party kexts, so the manifest's outside list has it
VERSION="$VERSION" sh "$SELF/build-kext.sh" "$OUT/kext" >&2
rm -rf "$STAGE/Library/Extensions/RecaulkKPI.kext"
mkdir -p "$STAGE/Library/Extensions"
cp -R "$OUT/kext/RecaulkKPI.kext" "$STAGE/Library/Extensions/"
# platform: kextd refuses a kext writable by anyone but root (kext_tools 10.9, checkFileOwnership)
find "$STAGE/Library/Extensions/RecaulkKPI.kext" -type d -exec chmod 755 {} +
find "$STAGE/Library/Extensions/RecaulkKPI.kext" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/Library/Extensions/RecaulkKPI.kext/Contents/MacOS/RecaulkKPI"
# spec: README.md "The kernel-fixes kext" -- the second kext, staged as the first, and the LaunchDaemon that loads it
#       at boot (not in Safe Boot), which uninstall unloads and removes with it
KEXT_SRC="$MAVERICKS_ROOT/src/kfix" KEXT_NAME=RecaulkKernelFixes VERSION="$VERSION" sh "$SELF/build-kext.sh" "$OUT/kfix" >&2
rm -rf "$STAGE/Library/Extensions/RecaulkKernelFixes.kext"
cp -R "$OUT/kfix/RecaulkKernelFixes.kext" "$STAGE/Library/Extensions/"
find "$STAGE/Library/Extensions/RecaulkKernelFixes.kext" -type d -exec chmod 755 {} +
find "$STAGE/Library/Extensions/RecaulkKernelFixes.kext" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/Library/Extensions/RecaulkKernelFixes.kext/Contents/MacOS/RecaulkKernelFixes"
mkdir -p "$STAGE/Library/LaunchDaemons"
cp "$MAVERICKS_ROOT/packaging/kernelfixes-loader.plist" "$STAGE/Library/LaunchDaemons/dev.mavergreen.recaulk.kernelfixes.plist"
chmod 644 "$STAGE/Library/LaunchDaemons/dev.mavergreen.recaulk.kernelfixes.plist"

SCR="$OUT/pkg-scripts"; rm -rf "$SCR"
sh "$SCRIPTS/stage_product.sh" --stage "$STAGE" --product recaulk \
  --name "Recaulk for Mavericks" --version "$VERSION" --updater-app "$UPD_APP" \
  --postinstall-hook "$MAVERICKS_ROOT/packaging/postinstall-hook.sh" --scripts-out "$SCR" \
  --boot-kext dev.mavergreen.recaulk.kernelfixes >&2

mkdir -p "$OUT/component"
comp="$OUT/component/recaulk-component.pkg"
sh "$SCRIPTS/build_component_pkg.sh" --root "$STAGE" --identifier "$ID" --version "$VERSION" --scripts "$SCR" \
  --install-location / --out "$comp" >&2

final="$OUT/recaulk-${VERSION}.pkg"
sh "$SCRIPTS/set_install_floor.sh" --identifier "$ID" --title "Recaulk for Mavericks ${VERSION}" \
  --component "$comp" --out "$final" --host-arch x86_64 --require-scripts >&2

pin() { tr -d ' \t\n' < "$MAVERICKS_ROOT/components/$1/version"; }
set -- variant=release arch=x86_64 prefix=/usr/local/mavergreen/recaulk pkg="recaulk-$VERSION.pkg" identifier="$ID" \
  clang22="$(pin clang22)" cctools="$(pin cctools)" drydock="$(pin drydock)" macports-legacy-support="$(macports_pin REF)"
for f in "$BUILD/build-tools.txt" "$(dirname "$UPD_APP")/build-tools.txt"; do
  while IFS= read -r l; do set -- "$@" "$l"; done < "$f"
done
sh "$SCRIPTS/build-info.sh" "$OUT/build-info-release.txt" "$@"

printf '%s\n' "$final"
