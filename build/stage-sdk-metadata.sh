#!/bin/sh
# platform: host-agnostic
# usage: sh build/stage-sdk-metadata.sh SOURCE_DIR DEST_DIR
#        validates SOURCE_DIR/recipes.json and copies it alone to DEST_DIR/recipes.json.
#        DEST_DIR must not exist; on any refusal it is not created. Exit 0 staged, nonzero refused.
set -eu
[ $# -eq 2 ] || { echo "stage-sdk-metadata: usage: stage-sdk-metadata.sh SOURCE_DIR DEST_DIR" >&2; exit 2; }
src="$1" dest="$2"
SELF="$(cd "$(dirname "$0")" && pwd)"
# platform: off macOS, shipyard's install action puts no shipyard-cmake on PATH; the runner's own
#           cmake (3.19 or later, for string(JSON)) validates the recipes there
SC="$(command -v shipyard-cmake || command -v cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
[ -x "$SC" ] || { echo "stage-sdk-metadata: no shipyard-cmake or cmake to validate the recipes with" >&2; exit 1; }
[ ! -e "$dest" ] && [ ! -L "$dest" ] || { echo "stage-sdk-metadata: $dest already exists" >&2; exit 1; }
[ -f "$src/recipes.json" ] || { echo "stage-sdk-metadata: no $src/recipes.json" >&2; exit 1; }
abs="$(cd "$src" && pwd)/recipes.json"

parent="$(dirname "$dest")"
mkdir -p "$parent"
tmp="$(mktemp -d "$parent/.stage-sdk-metadata.XXXXXX")"   # platform: 10.9 BSD mktemp requires a template
trap 'rm -rf "$tmp"' EXIT

if ! out="$("$SC" -DRECIPES="$abs" -DREASON_FILE="$tmp/reason" -P "$SELF/sdk-metadata-validate.cmake" 2>&1)"; then
  if [ -s "$tmp/reason" ]; then
    cat "$tmp/reason" >&2
  else
    printf 'stage-sdk-metadata: %s is not valid recipe data:\n%s\n' "$abs" "$out" >&2
  fi
  exit 1
fi
cp "$abs" "$tmp/recipes.json"
cmp -s "$abs" "$tmp/recipes.json" || { echo "stage-sdk-metadata: the staged copy differs from $abs" >&2; exit 1; }
# platform: mktemp -d creates its directory 0700, and the pkg installs this tree as root, so without
#           this only root could read the recipes (Recaulk 20261107.2 shipped that way)
chmod 755 "$tmp"
chmod 644 "$tmp/recipes.json"
mv "$tmp" "$dest"
trap - EXIT
