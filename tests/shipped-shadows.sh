#!/bin/sh
# platform: host-agnostic
# spec: README.md "How to use" -- share/recaulk/image-local-shadows.txt is build/image-local-shadows.txt, so a
#       consumer that links a subset of librecaulk.a (swift's runtime libraries) reads which of 10.9's exports a
#       member deliberately shadows from the Recaulk it fetched, rather than keeping a copy that drifts
set -eu
cd "$(dirname "$0")/.."
. tests/helpers/built.sh
shipped="$T/share/recaulk/image-local-shadows.txt"
[ -f "$shipped" ] || { echo "FAIL: $shipped is not staged"; exit 1; }
cmp -s build/image-local-shadows.txt "$shipped" || { echo "FAIL: $shipped differs from build/image-local-shadows.txt"; exit 1; }
