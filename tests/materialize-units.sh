#!/bin/sh
# platform: host-agnostic
# spec: tests/c/materialize_units.c -- the materializer's SHA-256 and JSON reader
set -eu
cd "$(dirname "$0")/.."
d="$(mktemp -d "${TMPDIR:-/tmp}/materialize-units.XXXXXX")"
trap 'rm -rf "$d"' EXIT
sh build/build-materialize.sh unit "$d/units" tests/c/materialize_units.c
# platform: openssl dgst is on 10.9, modern macOS and Linux alike; shasum is perl, which 10.9 without CLT may lack
want="$(openssl dgst -sha256 sdk-metadata/recipes.json | sed 's/.*= *//')"
"$d/units" "$PWD/sdk-metadata/recipes.json" "$want"
